rule all:
    input:
        "X_sample_predictions_readable.csv"

# 1️⃣ Run the main bash pipeline
rule run_pipeline:
    input:
        fastq1="data/ERR12322786_1.fastq.gz",
        fastq2="data/ERR12322786_2.fastq.gz"
    output:
        "analysis_results/counts/gene_counts.txt"
    shell:
        """
        bash bash.sh
        """

# 2️⃣ Clean feature matrix
rule clean_matrix:
    input:
        "analysis_results/counts/gene_counts.txt"
    output:
        "analysis_results/scaled_count_selected_samples.csv"
    shell:
        """
        papermill cleaning.ipynb cleaning_executed.ipynb -p input_file {input} -p output_file {output}
        """

# 3️⃣ Run prediction
rule predict_antibiotic:
    input:
        model="antibiotic_model.pkl",
        features="analysis_results/scaled_count_selected_samples.csv"
    output:
        "X_sample_predictions_readable.csv"
    shell:
        """
        papermill prediction.ipynb prediction_executed.ipynb -p input_file {input.features} -p model_file {input.model} -p output_file {output}
        """
