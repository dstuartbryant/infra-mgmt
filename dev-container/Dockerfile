# Dockerfile for astro service
FROM python:3.12-slim

# Install repo-specific requirements if any
RUN apt-get update && apt-get install -y \
    make \
    curl \
    unzip \
    git \
    zsh \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 from official source
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

# Install Terraform (pin version)
ENV TERRAFORM_VERSION=1.13.0

RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip

# Verify installation
RUN terraform --version


# Set the working directory
WORKDIR /app/tf


RUN pip install poetry
RUN pip install pipx
RUN pipx install tox --force



RUN chsh -s $(which zsh) root &&     sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" &&     git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k &&     sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc

COPY ./zsh/.zshrc /root/.zshrc
COPY ./zsh/my_home_config.zsh /root/.oh-my-zsh/custom/my_home_config.zsh
COPY ./zsh/.p10k.zsh /root/.p10k.zsh

RUN git config --global core.editor "nano"
RUN git config --global user.name "stuart"
RUN git config --global user.email "stuart@spacewego.com"

