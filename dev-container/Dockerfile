# Use the official AWS CLI image
FROM amazon/aws-cli:latest

# Install Terraform, Node.js, Gemini CLI, and other base requirements
RUN yum swap -y curl-minimal curl && \
    yum update -y && \
    yum install -y yum-utils shadow-utils && \
    yum-config-manager \
    --add-repo \
    https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo && \
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - && \
    yum install -y \
    terraform \
    nodejs \
    jq \
    git \
    zsh \
    make \
    unzip \
    nano \
    ca-certificates \
    gnupg && \
    npm install -g @google/gemini-cli && \
    yum clean all

# Add aliases
RUN echo "alias ll='ls -l'" >> /etc/profile.d/aliases.sh &&     echo "alias ccc='clear'" >> /etc/profile.d/aliases.sh

# Set the working directory
WORKDIR /app/tf

# Keep the container running
CMD ["tail", "-f", "/dev/null"]