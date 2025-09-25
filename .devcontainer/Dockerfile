FROM docker.io/debian:stable

RUN apt update && apt install -y curl fish git sudo

RUN groupadd vscode; useradd -m -g vscode vscode

RUN echo "vscode ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vscode

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt install -y nodejs && \
    npm install -g @google/gemini-cli
