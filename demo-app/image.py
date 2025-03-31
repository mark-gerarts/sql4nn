import streamlit as st
import settings
import torch
import duckdb as db
import pandas as pd
import numpy as np
from model import Net
from PIL import Image, ImageFilter, ImageEnhance


@st.cache_data
def get_eval_query():
    with open(settings.EVAL_QUERY_PATH) as file:
        return file.read()


@st.cache_resource
def get_model():
    model = Net()
    model.load_state_dict(torch.load(settings.MODEL_PATH, weights_only=True))
    model.eval()

    return model


def eval_image_sql(con, image):
    try:
        con.execute("BEGIN TRANSACTION")
    except db.TransactionException:
        con.execute("ROLLBACK")
        con.execute("BEGIN TRANSACTION")

    con.execute("TRUNCATE input")

    rows = []
    for i, pixel in enumerate(image.flatten()):
        rows.append([0, i + 1, pixel.item()])

    df = pd.DataFrame(rows)
    con.execute("INSERT INTO input SELECT * FROM df")

    eval_query = get_eval_query()
    results_df = con.sql(eval_query).df()
    con.execute("COMMIT")

    predicted_digit = results_df["log_softmax"].idxmax()

    return results_df, predicted_digit


def eval_image_model(model, image):
    image_tensor = torch.tensor(image, dtype=torch.float32)
    result = model(image_tensor)
    result_df = pd.DataFrame(result.detach().numpy())

    return result_df, torch.argmax(result)


def mnistify_image(image):
    """
    Convert the image into grayscale and apply some transformations to make it
    look more like an MNIST image (i.e. a bit more pixelated)
    """
    image = Image.fromarray(image.astype(np.uint8))
    image = image.convert("L")  # grayscale
    image = image.filter(ImageFilter.GaussianBlur(radius=3))
    image = ImageEnhance.Contrast(image).enhance(1.5)
    image = image.resize((28, 28), Image.NEAREST)
    image = image.resize((280, 280), Image.NEAREST)
    image = image.resize((28, 28))

    return image
