"""Focused host/mock checks; these do not establish real assay execution."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tests/test_real_mode_fixtures.sh'
TEXT = SCRIPT.read_text()
CONFIG = TEXT.split('<<\'EOF\'\nprocess {', 1)[1].split('\nEOF', 1)[0]
CONFIG = 'process {' + CONFIG
spec = importlib.util.spec_from_file_location('retention', ROOT / 'tests/retain_fixture_evidence.py')
retention = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retention)


class HarnessTests(unittest.TestCase):
    def test_all_nextflow_calls_use_fixture_config(self):
        calls = re.findall(r'nextflow -log .*?(?=\n  assert_|\nassert_)', TEXT, re.S)
        self.assertEqual(len(calls), 4)
        for call in calls:
            self.assertIn('-c "$FIXTURE_CONFIG"', call)
            self.assertIn('-with-trace ', call)
        for assertion in ('RNA fixture gene counts missing', 'RNA fixture output validation reported errors',
                          'ATAC fixture RE counts missing', 'ATAC fixture output validation reported errors',
                          'WGS fixture BAM missing', 'WGS fixture VCF missing',
                          'WGS fixture output validation reported errors',
                          'strict missing FastQC diagnostic absent', 'strict missing STAR diagnostic absent',
                          'strict missing BWA-MEM2 diagnostic absent'):
            self.assertIn(assertion, TEXT)

    def test_retention_is_bounded_and_excludes_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp) / 'scratch', Path(tmp) / 'evidence'
            source.mkdir(); target.mkdir()
            (source / 'fixture_resources.config').write_text(CONFIG)
            task = source / 'rna_work/ab/failed'
            (task / 'logs/star').mkdir(parents=True)
            (task / '.command.sh').write_text('STAR command')
            (task / '.exitcode').write_text('42')
            (task / 'logs/star/error.log').write_bytes(b'x' * 300000 + b'causal error')
            (task / 'huge.bam').write_text('never copy')
            (source / 'linked.out').symlink_to(task / 'huge.bam')
            for n in range(205):
                (source / f'{n:03}.out').write_bytes(b'x' * 300000)
            retention.retain(source, target, 42)
            manifest = json.loads((target / 'retention.json').read_text())
            self.assertEqual(manifest['fixture_exit_status'], 42)
            self.assertLessEqual(len(manifest['files']), 200)
            self.assertGreater(manifest['omitted_files'], 0)
            self.assertLessEqual(sum(r['retained_bytes'] for r in manifest['files']), 16 * 1024 * 1024)
            self.assertTrue(all(r['retained_bytes'] <= 256 * 1024 for r in manifest['files']))
            self.assertTrue((target / 'rna_work/ab/failed/logs/star/error.log').read_bytes().endswith(b'causal error'))
            self.assertFalse(list(target.rglob('*.bam')))
            self.assertFalse((target / 'linked.out').exists())

    def test_original_failure_cleanup_and_caller_preservation(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fake = base / 'nextflow'
            fake.write_text('''#!/usr/bin/env bash
printf '%s' "$PWD" > "$SCRATCH_RECORD"
mkdir -p reference_quality_work/aa/failure/logs/tool
printf 'task command' > reference_quality_work/aa/failure/.command.sh
printf '43' > reference_quality_work/aa/failure/.exitcode
printf 'tool cause' > reference_quality_work/aa/failure/logs/tool/error.log
exit 43
''')
            fake.chmod(0o755)
            record = base / 'scratch.txt'
            env = dict(os.environ, PATH=f'{base}:{os.environ["PATH"]}', SCRATCH_RECORD=str(record))
            evidence = base / 'caller'
            evidence.mkdir()
            sentinel = evidence / 'keep.txt'
            sentinel.write_text('caller content')
            for retain in (False, True, True):
                args = ['bash', str(SCRIPT), '--strict']
                if retain:
                    args += ['--evidence-dir', 'caller']
                result = subprocess.run(args, cwd=base, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 43, result.stdout + result.stderr)
                self.assertFalse(Path(record.read_text()).exists())
                self.assertEqual(sentinel.read_text(), 'caller content')
            children = list(evidence.glob('fixtures.*'))
            self.assertEqual(len(children), 2)
            for child in children:
                self.assertEqual(json.loads((child / 'retention.json').read_text())['fixture_exit_status'], 43)
                self.assertTrue((child / 'reference_quality_work/aa/failure/.command.sh').is_file())
                self.assertTrue((child / 'fixture_validation/fixture_validation.tsv').is_file())
            wrapper = base / 'python-wrapper'
            wrapper.write_text('#!/usr/bin/env bash\n'
                               'case "$1" in */retain_fixture_evidence.py) exit 77;; esac\n'
                               f'exec {shlex.quote(sys.executable)} "$@"\n')
            wrapper.chmod(0o755)
            result = subprocess.run(args, cwd=base, env=dict(env, PYTHON=str(wrapper)),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 43)
            self.assertIn('evidence retention failed (77)', result.stderr)
            self.assertFalse(Path(record.read_text()).exists())
            self.assertEqual(sentinel.read_text(), 'caller content')

    @unittest.skipUnless(shutil.which('nextflow'), 'Nextflow unavailable')
    def test_effective_selector_precedence(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            shutil.copy(ROOT / 'nextflow.config', base / 'nextflow.config')
            (base / 'fixture.config').write_text(CONFIG)
            (base / 'main.nf').write_text('''nextflow.enable.dsl=2
process RNA_STAR_INDEX {
    label 'process_star_index'
    cpus 8
    memory '32 GB'
    output: path 'resources.txt'
    script:
    """
    echo '${task.cpus} ${task.memory.toGiga()}' > resources.txt
    """
}
workflow { RNA_STAR_INDEX().view { it.text.trim() } }
''')
            result = subprocess.run(['nextflow', 'run', str(base), '-ansi-log', 'false', '-c', str(base / 'fixture.config')],
                                    cwd=base, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'(?m)^1 4$')


if __name__ == '__main__':
    unittest.main()
