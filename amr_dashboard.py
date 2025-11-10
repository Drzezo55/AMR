import streamlit as st
import pandas as pd
import joblib
import plotly.express as px

import plotly.graph_objects as go

st.title("AMR Prediction Dashboard 🧬")

# Upload feature matrix
uploaded = st.file_uploader("Upload processed count matrix (CSV)", type=["csv"])
model_file = "antibiotic_model.pkl"

if uploaded:
    df = pd.read_csv(uploaded, index_col=0)

    st.write("Data preview:", df.head())

    # Load model and predict
    model = joblib.load(model_file)
    model_features = model.feature_names_in_
    df = df[model_features]
    preds = model.predict(df)

    # Predicted antibiotics (must match your model’s output count)
    antibiotic_cols = [
        'AMI  Interpretation', 'AMP Interpretation', 'AZI Interpretation',
        'FOT Interpretation', 'TAZ  Interpretation', 'CHL Interpretation',
        'CIP Interpretation', 'COL Interpretation', 'GEN Interpretation',
        'MERO Interpretation', 'NAL  Interpretation',
        'TET  Interpretation', 'TGC  Interpretation', 'TMP Interpretation'
    ]

    preds_df = pd.DataFrame(preds, index=df.index, columns=antibiotic_cols)

    # Optional: map predictions to R/S/I (assuming model outputs 0,1,2)
    mapping = {0: "S", 1: "I", 2: "R"}
    preds_readable = preds_df.replace(mapping)

    st.subheader("Predicted Resistance Profile")
    st.dataframe(preds_readable)



    # ✅ Prepare data for visualization
    plot_df = preds_readable.melt(ignore_index=False, var_name="Antibiotic", value_name="Interpretation")
    summary = plot_df.groupby(["Antibiotic", "Interpretation"]).size().reset_index(name="Count")

    # ✅ Plot: stacked horizontal bar chart
    fig = px.bar(
        summary,
        x="Count",
        y="Antibiotic",
        color="Interpretation",
        orientation="h",
        color_discrete_map={"S": "lightgreen", "I": "gold", "R": "tomato"},
        title="Resistance Distribution per Antibiotic"
    )

    fig.update_layout(
        xaxis_title="Number of Samples",
        yaxis_title="Antibiotic",
        barmode="stack",
        height=700
    )

    st.plotly_chart(fig, use_container_width=True)

    # Download predictions
    st.download_button("Download predictions",
                       preds_readable.to_csv().encode(),
                       "predictions.csv")
