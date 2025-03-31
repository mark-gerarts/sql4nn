import streamlit as st
import duckdb as db
import numpy as np
import saliency
from PIL import Image
from streamlit_drawable_canvas import st_canvas
import settings
import image
import multimodel


@st.cache_resource
def connect_to_db():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_SINGLE}'")

    return con


con_epochs = multimodel.connect_to_db_multiple_epochs()
con_sizes = multimodel.connect_to_db_multiple_sizes()
model = image.get_model()


st.title("Querying multiple models")
st.text("Querying a custom drawing on both previous databases.")

col1, col2 = st.columns(2)

with col1:
    canvas_result = st_canvas(
        width=280,
        height=280,
        background_color="#000",
        stroke_color="#FFF",
    )

img = canvas_result.image_data
has_image = img is not None and not np.all(img == img[0, 0])

with col2:
    if has_image:
        mnist_image = image.mnistify_image(img)
        mnist_image = mnist_image.resize((280, 280), Image.BOX)
        st.image(mnist_image)

st.divider()

if has_image:
    img = image.mnistify_image(img)
    img = np.array(img) / 255.0
    img = np.expand_dims(img, axis=0)
    img = np.expand_dims(img, axis=1)
    img = (img - 0.1307) / 0.3081

    st.text("Prediction across model sizes:")
    with st.spinner("Querying across sizes..."):
        _, sql_prediction = multimodel.eval_image_sql(con_sizes, img)
        final_df = multimodel.pivot(sql_prediction)
        st.dataframe(final_df)

    st.text("Prediction across epochs:")
    with st.spinner("Querying across epochs..."):
        _, sql_prediction = multimodel.eval_image_sql(con_epochs, img)
        final_df = multimodel.pivot(sql_prediction)
        st.dataframe(final_df)
