import streamlit as st
import image

st.title("Eval query with softmax")

query = image.get_eval_query()
st.code(query, language="sql")
