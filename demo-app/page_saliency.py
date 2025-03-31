import streamlit as st
import duckdb as db
import numpy as np
import saliency
from PIL import Image
from streamlit_drawable_canvas import st_canvas
import settings
import image


@st.cache_resource
def connect_to_db():
    con = db.connect()
    con.execute(f"IMPORT DATABASE '{settings.DB_SINGLE}'")

    return con


@st.dialog("Eval query")
def show_eval_query():
    with open(settings.EVAL_QUERY_PATH) as file:
        eval_query = file.read()

    st.code(eval_query, language="sql")


con = connect_to_db()
model = image.get_model()


st.title("Saliency")

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

col1, col2 = st.columns(2)


with col1:
    if has_image:
        img = image.mnistify_image(img)

        # Convert it into the format the models expect.
        img = np.array(img) / 255.0
        img = np.expand_dims(img, axis=0)
        img = np.expand_dims(img, axis=1)
        img = (img - 0.1307) / 0.3081

        model_result, model_prediction = image.eval_image_model(model, img)
        sql_result, sql_prediction = image.eval_image_sql(con, img)

        st.markdown(
            f"We compare the output of the PyTorch model and that of the SQL query. The prediction is **{sql_prediction}**."
        )

        combined_result = model_result.T
        combined_result["SQL output"] = sql_result.iloc[:, 2]
        combined_result = combined_result.rename(columns={0: "Model output"})
        st.dataframe(combined_result)

with col2:
    if has_image:
        with st.spinner("Saliency map:"):
            saliency_map = saliency.get_saliency_map(con)
            saliency_image = saliency.to_heatmap_image(saliency_map)
            st.text("Actual saliency")
            st.image(saliency_image)
