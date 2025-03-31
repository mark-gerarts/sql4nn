import streamlit as st
import settings

with open(settings.BASIC_EVAL_QUERY_PATH) as file:
    eval_query = file.read()

st.title("Eval query")
st.code(eval_query, language="sql")
