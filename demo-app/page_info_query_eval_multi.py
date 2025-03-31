import streamlit as st
import multimodel

st.title("Eval query - Multimodel")

query = multimodel.get_eval_query()
st.code(query, language="sql")
