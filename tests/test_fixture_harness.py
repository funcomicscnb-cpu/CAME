"""Focused host/mock checks; these do not establish real assay execution."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
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
    def test_workflow_evidence_initialization_and_upload(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        job = workflow.split('\n  real-mode-ci:', 1)[1].split('\n  deseq2-validation:', 1)[0]
        before_steps, steps = job.split('    steps:\n', 1)
        self.assertNotIn('runner.temp', before_steps)
        self.assertNotIn('EVIDENCE_DIR', before_steps)
        first = steps.split('\n      - name:', 1)[0]
        self.assertIn('- name: Initialize evidence directory', first)
        initialization = first.split('        run: |\n', 1)[1]
        initialization = '\n'.join(line[10:] for line in initialization.splitlines())
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env_file = base / 'github-env'
            env = dict(os.environ, RUNNER_TEMP=str(base / 'runner temp'), GITHUB_ENV=str(env_file))
            result = subprocess.run(['bash', '-e', '-c', initialization], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(env_file.read_text(), f'EVIDENCE_DIR={base}/runner temp/came-real-mode-evidence\n')
            self.assertTrue((base / 'runner temp/came-real-mode-evidence').is_dir())
            # A failed first step must not export an empty/unsafe evidence path.
            env_file.unlink()
            blocked = base / 'file'
            blocked.write_text('not a directory')
            result = subprocess.run(['bash', '-e', '-c', initialization],
                                    env=dict(env, RUNNER_TEMP=str(blocked)), capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(env_file.exists())
        upload = steps.split('- name: Upload compact real-mode evidence', 1)[1]
        self.assertIn('if: always()', upload)
        self.assertIn('path: ${{ runner.temp }}/came-real-mode-evidence/\n', upload)
        self.assertNotIn('env.EVIDENCE_DIR', upload)
        self.assertIn('shell: bash', before_steps)  # Actions supplies -eo pipefail.
        self.assertIn('fixture_status=${PIPESTATUS[0]}', steps)
        self.assertIn('exit "$fixture_status"', steps)
        strict = steps.split('- name: Run strict real-mode fixtures\n', 1)[1].split('\n      - name:', 1)[0]
        strict_run = strict.split('        run: |\n', 1)[1]
        strict_run = '\n'.join(line[10:] for line in strict_run.splitlines())
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            docker = base / 'docker'
            docker.write_text('#!/usr/bin/env bash\nprintf "container failure\\n"\nexit 43\n')
            docker.chmod(0o755)
            result = subprocess.run(['bash', '-eo', 'pipefail', '-c', strict_run],
                                    env=dict(os.environ, PATH=f'{base}:{os.environ["PATH"]}', EVIDENCE_DIR=tmp),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 43, result.stdout + result.stderr)
            self.assertEqual((base / 'fixture-exit-status.txt').read_text(), '43\n')
            self.assertEqual((base / 'fixtures.log').read_text(), 'container failure\n')
        fast = workflow.split('\n  fast-validation:', 1)[1].split('\n  end-to-end-stub:', 1)[0]
        install = fast.index('- name: Install Nextflow')
        tests = fast.index('python3 tests/test_fixture_harness.py')
        self.assertLess(install, tests)
        real_tests = fast.split('- name: Real-mode unit tests', 1)[1].split('\n      - name:', 1)[0]
        self.assertIn('python3 tests/test_fixture_harness.py', real_tests)

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

    def test_star_out_logs_from_failed_and_incomplete_tasks(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp) / 'scratch', Path(tmp) / 'evidence'
            source.mkdir(); target.mkdir()
            expected = []
            for name, status in [('failed', '42'), ('incomplete', None), ('successful', '0')]:
                task = source / 'rna_work/ab' / name
                (task / 'star').mkdir(parents=True)
                (task / 'logs/star').mkdir(parents=True)
                (task / '.command.sh').write_text('STAR')
                if status is not None:
                    (task / '.exitcode').write_text(status)
                for relative in ('star/sample.Log.out', 'star/sample.Log.progress.out',
                                 'star/sample.Log.final.out', 'logs/star/sample.Log.out', 'Log.out'):
                    log = task / relative
                    log.write_bytes(b'x' * 300000 + b'STAR causal tail')
                    if status != '0':
                        expected.append(log.relative_to(source))
                (task / 'star/sample.Aligned.out.bam').write_text('excluded BAM')
                (task / 'star/SA').write_text('excluded index')
                (task / 'star/linked.out').symlink_to(task / 'Log.out')
                (task / 'logs/linked').symlink_to(task / 'star', target_is_directory=True)
            retention.retain(source, target, 42)
            for relative in expected:
                self.assertTrue((target / relative).read_bytes().endswith(b'STAR causal tail'))
                self.assertEqual((target / relative).stat().st_size, 256 * 1024)
            retained = {row['path'] for row in json.loads((target / 'retention.json').read_text())['files']}
            self.assertEqual(retained, {str(p) for p in expected} | {
                f'rna_work/ab/{name}/{file}' for name in ('failed', 'incomplete')
                for file in (('.command.sh', '.exitcode') if name == 'failed' else ('.command.sh',))})

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
            evidence.chmod(0o750)
            sentinel = evidence / 'keep.txt'
            sentinel.write_text('caller content')
            sentinel.chmod(0o600)
            caller_stat, sentinel_stat = evidence.stat(), sentinel.stat()
            for retain in (False, True, True):
                args = ['bash', str(SCRIPT), '--strict']
                if retain:
                    args += ['--evidence-dir', 'caller']
                result = subprocess.run(args, cwd=base, env=env, capture_output=True, text=True, umask=0o077)
                self.assertEqual(result.returncode, 43, result.stdout + result.stderr)
                self.assertFalse(Path(record.read_text()).exists())
                self.assertEqual(sentinel.read_text(), 'caller content')
            children = list(evidence.glob('fixtures.*'))
            self.assertEqual(len(children), 2)
            for child in children:
                for path in (child, *child.rglob('*')):
                    mode = stat.S_IMODE(path.stat().st_mode)
                    required = 0o555 if path.is_dir() else 0o444
                    self.assertEqual(mode & required, required, str(path))
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
            # Permission failures must also preserve the original fixture status.
            chmod = base / 'chmod'
            chmod.write_text('#!/usr/bin/env bash\nexit 78\n')
            chmod.chmod(0o755)
            result = subprocess.run(args, cwd=base, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 43)
            self.assertIn('fixture evidence permission adjustment failed', result.stderr)
            self.assertFalse(Path(record.read_text()).exists())
            for path, original in ((evidence, caller_stat), (sentinel, sentinel_stat)):
                current = path.stat()
                self.assertEqual((current.st_mode, current.st_uid, current.st_gid),
                                 (original.st_mode, original.st_uid, original.st_gid))
            self.assertEqual(sentinel.read_text(), 'caller content')
            self.assertEqual({p.name for p in evidence.iterdir() if not p.name.startswith('fixtures.')}, {'keep.txt'})

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
