import numpy as np
import matplotlib.pyplot as plt
from io import BytesIO
import settings
from concurrent.futures import ProcessPoolExecutor


with open(settings.EVAL_SALIENCY_PATH) as file:
    query = file.read()


con = None


def fetch_data(i):
    return con.execute(query, [i]).fetchall()


def get_saliency_map(_con):
    # This is a hack to avoid multiple connections/pickle issues...
    global con
    con = _con

    actual_result = con.execute(query, [-1]).fetchall()
    max_actual = max([row[1] for row in actual_result])
    guessed_digit = max(range(len(actual_result)), key=lambda i: actual_result[i][1])

    with ProcessPoolExecutor() as executor:
        all_results = list(executor.map(fetch_data, range(1, 28 * 28 + 1)))

    diffs = []
    for results in all_results:
        sal_result = results[guessed_digit][1]
        diffs.append(abs(sal_result - max_actual))

    return np.array(diffs).reshape((28, 28))


def to_heatmap_image(saliency_map):
    plt.imshow(saliency_map, cmap="jet")
    plt.axis("off")

    buf = BytesIO()
    plt.savefig(buf, format="png")
    buf.seek(0)

    plt.close()

    return buf
