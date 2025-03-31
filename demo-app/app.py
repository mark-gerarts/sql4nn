import streamlit as st

page_saliency = st.Page(
    "page_saliency.py",
    title="Saliency",
)
page_multimodel_epochs = st.Page(
    "page_multimodel_epochs.py",
    title="MNIST input - epochs",
)
page_multimodel_size = st.Page(
    "page_multimodel_size.py",
    title="MNIST input - size",
)
page_multimodel_draw = st.Page(
    "page_multimodel_draw.py",
    title="Custom input",
)

pg = st.navigation(
    {
        "Intro": [
            st.Page("page_intro.py", title="SQL4NN"),
        ],
        "Eval": [
            st.Page("page_eval.py", title="Model evaluation"),
        ],
        "Multimodel": [
            page_multimodel_epochs,
            page_multimodel_size,
            page_multimodel_draw,
        ],
        "Model queries": [
            st.Page("page_model_queries_basic.py", title="Basic model queries"),
            st.Page("page_model_queries_pwl.py", title="Piecewise Linear Functions"),
        ],
        "Saliency": [page_saliency],
        "Info": [
            st.Page("page_info_database_schema.py", title="Database schema"),
            st.Page(
                "page_info_database_schema_multimodel.py",
                title="Database schema - multimodel",
            ),
            st.Page("page_info_query_eval.py", title="Eval query"),
            st.Page("page_info_query_eval_w_softmax.py", title="Eval query - softmax"),
            st.Page("page_info_query_eval_multi.py", title="Eval query - multimodel"),
        ],
    }
)
pg.run()
