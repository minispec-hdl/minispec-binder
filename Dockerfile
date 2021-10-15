# Derived from minispec's Vagrantfile, using a 2-stage build to reduce final container size

# Bump this when meaningful changes happen to the minispec repo to invalidate docker's cache and rebuild from scratch
ARG VERSION="2021-10-15"

FROM ubuntu:20.04 as stage1

# Packages
ENV DEBIAN_FRONTEND noninteractive
# 1. Basics, direct minispec deps (include bsc deps), antlr deps, antlr runtime build
# 2. Yosys deps
# 3. Notebook / netlistsvg deps
RUN apt-get -y update && \
    apt-get -y install sudo vim wget scons git build-essential g++ libxft2 libgmp10  openjdk-8-jdk-headless  cmake pkg-config uuid-dev && \
    apt-get -y install build-essential clang bison flex libreadline-dev gawk tcl-dev libffi-dev pkg-config python3 graphviz && \
    apt-get -y install python3-pip npm

# create user with a home directory
ARG NB_USER
ARG NB_UID
ENV USER ${NB_USER}
ENV HOME /home/${NB_USER}

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}
WORKDIR ${HOME}
USER ${USER}

# Download bsc
ENV BSVER "bsc-2021.07-ubuntu-20.04"
ENV BSREL "2021.07"
RUN echo "Downloading bsc ${BSREL} / ${BSVER}" && \
    wget -nc -nv https://github.com/B-Lang-org/bsc/releases/download/${BSREL}/${BSVER}.tar.gz && \
    tar xzf ${BSVER}.tar.gz && \
    mv ${BSVER} bluespec
ENV PATH ${HOME}/bluespec/bin:${PATH}

# Clone and build minispec
RUN git clone https://github.com/minispec-hdl/minispec && \
    cd minispec && scons -j16
ENV PATH ${HOME}/minispec:${HOME}/minispec/synth:${PATH}

# Download yosys
RUN wget -nc -nv https://github.com/YosysHQ/yosys/archive/yosys-0.8.tar.gz && \
    tar xzf yosys-0.8.tar.gz && \
    cd yosys-yosys-0.8 && make -j16 yosys-abc && cd abc && git apply ${HOME}/minispec/synth/abc.patch && make clean && \
    cd .. && sed -i "s/ABCREV = ae6716b/ABCREV = default/g" Makefile && make clean && PREFIX=${HOME}/yosys make -j16 install
ENV PATH ${HOME}/yosys/bin:${PATH}

# Install netlistsvg
USER root
RUN npm install -g netlistsvg

# Install notebook package
RUN pip install --upgrade setuptools pip && \
    ./minispec/jupyter/install-jupyter.sh && \
    ln -s ${PWD}/minispec/jupyter/minispeckernel.py /usr/local/lib/python3.8/dist-packages/ && \
    jupyter kernelspec install ${PWD}/minispec/jupyter/kernel/minispec && \
    rm -rf .local/

RUN pip install --no-cache nbgitpuller

# Cleanup
USER root
RUN rm -rf *.tar.gz minispec/build minispec/antlr* minispec/.git yosys-yosys-0.8 .cache && strip -S minispec/msc && strip -S minispec/minispec-combine && apt clean

USER ${NBUSER}

FROM ubuntu:20.04 as stage2
ARG NB_USER
ARG NB_UID

# Install only runtime deps
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && apt-get -y install build-essential g++ libxft2 libgmp10  libreadline8 gawk tcl libffi7  python3-pip npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN npm install -g netlistsvg && mkdir -p /opt

COPY --from=stage1 /home/${NB_USER}/bluespec /opt/bluespec
COPY --from=stage1 /home/${NB_USER}/minispec /opt/minispec
COPY --from=stage1 /home/${NB_USER}/yosys /opt/yosys
COPY --from=stage1 /home/${NB_USER}/notebook-5.7.8 /root/notebook-5.7.8

RUN pip install --no-cache --upgrade setuptools pip && \
    cd /root/notebook-5.7.8 && pip install . && \
    ln -s /opt/minispec/jupyter/minispeckernel.py /usr/local/lib/python3.8/dist-packages/ && \
    jupyter kernelspec install /opt/minispec/jupyter/kernel/minispec && \
    rm -rf /root/.cache && rm -rf /root/.local && rm -rf /root/.notebook-5.7.8
   
RUN pip install --no-cache nbgitpuller

# create user with a home directory
ENV USER ${NB_USER}
ENV HOME /home/${NB_USER}
RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}
WORKDIR ${HOME}
ENV PATH /opt/minispec/:/opt/minispec/synth:/opt/bluespec/bin:/opt/yosys/bin:${PATH}
