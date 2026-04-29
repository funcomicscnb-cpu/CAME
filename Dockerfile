FROM continuumio/miniconda3:24.5.0-0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY environment/conda-linux-64.lock /tmp/conda-linux-64.lock
RUN conda create -y -n came --file /tmp/conda-linux-64.lock \
    && conda clean -afy

ENV PATH="/opt/conda/envs/came/bin:${PATH}"

COPY . /came
WORKDIR /came

RUN nextflow -version
RUN python3 bin/check_real_mode_tools.py --mode strict --omics-types rnaseq,atacseq,wgs
