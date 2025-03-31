# Notebooks

Notebooks going through the implemented queries in a more blog-like style.

## Setup

```bash
python3 -m venv venv
. venv/bin/activate
pip install -r requirements.txt
```

## Building

The notebooks are bundled in HTML format using `jupyter-book`. To build the HTML
output:

```bash
jupyter-book build .
```

This requires a running Neo4j instance, which can be done using e.g. docker:

```bash
docker start neo4j || \
    docker run -d \
    -p 7474:7474 \
    -p 7687:7687 \
    -e NEO4J_dbms_security_auth__enabled=false \
    --name neo4j \
    neo4j:5.22.0
```
