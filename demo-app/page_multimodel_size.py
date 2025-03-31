from torchvision import datasets, transforms
import matplotlib.pyplot as plt
import streamlit as st
import multimodel


con = multimodel.connect_to_db_multiple_sizes()
eval_query = multimodel.get_eval_query()


st.title("Querying multiple models")
st.text("We compare the MNIST model to smaller versions. Each model has the same structure, but fewer hidden units.")

for i in range(0, 5):
    col1, col2 = st.columns([0.2, 0.8])

    with col1:
        dataset = datasets.MNIST(
            "../data", train=False, transform=transforms.ToTensor()
        )
        image, label = dataset[i]
        image_np = image.squeeze().numpy()

        fig, ax = plt.subplots()
        ax.imshow(image_np, cmap="gray")
        ax.axis("off")  # Hide the axes for a cleaner look
        st.pyplot(fig)

    with col2:
        with st.spinner("Querying..."):
            image = (image - 0.1307) / 0.3081
            _, sql_prediction = multimodel.eval_image_sql(con, image)
            
            final_df = multimodel.pivot(sql_prediction)
            st.dataframe(final_df)
