FROM debian:12.11-slim

RUN apt-get update && apt-get install -y \
  git \
  subversion \
  clang \
  libx11-6 \
  libunwind8 \
  --no-install-recommends && \
  rm -rf /var/lib/apt/lists/*

ENV MAX_LOGS="20"
ENV LOG_DIR="/var/log/glassminers"
ENV LOG_DATE_FORMAT="%Y-%m-%d-%H-%M-%S"

RUN mkdir -p ${LOG_DIR}

WORKDIR /usr/local/src
RUN mkdir -p jai && mkdir -p glassminers

RUN svn checkout svn://tealfire.de/svn/Jai/ -rHEAD jai
COPY . glassminers

RUN cd glassminers && ../jai/bin/jai first.jai -- server-release && cd ../
RUN mv glassminers/run_tree/server.out ./
RUN rm -rf jai/ && rm -rf glassminers/

COPY ./docker/server_script.sh ./
RUN chmod +x ./server_script.sh

EXPOSE 9876

CMD ["./server_script.sh"]