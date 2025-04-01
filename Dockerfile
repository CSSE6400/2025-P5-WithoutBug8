# 千万要注意，macOS必须这么写
FROM --platform=linux/arm64 ubuntu:22.04

ENV SQLALCHEMY_DATABASE_URI=sqlite:///:memory:

# Installing dependencies and cleaning up
RUN apt-get update && \
        apt-get install -y python3 python3-pip postgresql-client libpq-dev libcurl4-openssl-dev libssl-dev && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*
		
# Install pipenv
RUN pip3 install poetry

# Setting the working directory
WORKDIR /app

# Install pipenv dependencies
COPY pyproject.toml .
RUN poetry install --no-root

# Copying our application into the container
COPY bin bin
COPY todo todo

# Running our application
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["serve"]
