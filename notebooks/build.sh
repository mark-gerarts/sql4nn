#!/usr/bin/env sh
. venv/bin/activate

docker start neo4j || \
    docker run -d \
    -p 7474:7474 \
    -p 7687:7687 \
    -e NEO4J_dbms_security_auth__enabled=false \
    --name neo4j \
    neo4j:5.22.0

jupyter-book build .
