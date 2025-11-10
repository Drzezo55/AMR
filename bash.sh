reference/ref.fa#!/bin/bash
set -e
# ===========================================================
# Salmonella enterica pipeline
# Quality Control → Trimming → Alignment → Sorting → Counting
# ===========================================================

# ---- 0. Variables ----
REF="reference/GCF_000006945.2_ASM694v2_genomic.fna"
GTF="reference/GCF_000006945.2_ASM694v2_genomic.gff"
RAW_DIR="./data"
OUT_DIR="./analysis_results"
THREADS=8

mkdir -p $OUT_DIR/fastqc $OUT_DIR/trimmed $OUT_DIR/aligned $OUT_DIR/counts


# ---- 1. Check for required tools ----
echo "🔍 Checking for required tools..."

TOOLS=("fastqc" "fastp" "bwa" "samtools" "featureCounts")

for TOOL in "${TOOLS[@]}"; do
  if command -v $TOOL &>/dev/null; then
    echo "✅ $TOOL already installed."
  else
    echo "⚙️  Installing $TOOL..."
    if [[ "$TOOL" == "featureCounts" ]]; then
      # featureCounts is part of subread
      brew install brewsci/bio/subread || {
        echo "❌ Failed to install subread via Homebrew. Trying Conda..."
        if command -v conda &>/dev/null; then
          conda install -y -c bioconda subread || {
            echo "⚠️  Could not install featureCounts. Please install manually."
          }
        else
          echo "⚠️  Conda not found. Please install manually using:"
          echo "   brew install brewsci/bio/subread"
          echo "   OR conda install -c bioconda subread"
        fi
      }
    else
      brew install $TOOL || {
        echo "⚠️  Could not install $TOOL automatically. Please install manually."
      }
    fi
  fi
done

echo "🧩 All required tools are ready."


# ---- 2. Ensure reference files exist ----
if [ ! -f "$REF" ]; then
  echo "❌ Reference FASTA not found: $REF"
  exit 1
fi
if [ ! -f "$GTF" ]; then
  echo "⚠️  Annotation file not found: $GTF (featureCounts will be skipped)"
  USE_COUNTS=false
else
  USE_COUNTS=true
fi


# ---- 3. Handle compression consistency ----
echo "🗜️  Checking FASTQ compression..."
cd $RAW_DIR
for FILE in *.fastq *.fastq.gz; do
  [ -e "$FILE" ] || continue
  if [[ "$FILE" == *.gz ]]; then
    echo "Unzipping $FILE..."
    gunzip -f "$FILE"
  fi
done
cd - >/dev/null

# Optionally gzip them again for FastQC/fastp uniformity
echo "Compressing FASTQ files..."
for FILE in $RAW_DIR/*.fastq; do
  gzip -f "$FILE"
done


# ---- 4. Quality Control ----
echo "🚦 Running FastQC..."
fastqc $RAW_DIR/*.fastq.gz -t $THREADS -o $OUT_DIR/fastqc


# ---- 5. Trimming (fastp) ----
echo "✂️  Trimming reads with fastp..."
for R1 in $RAW_DIR/*_1.fastq.gz; do
  BASE=$(basename $R1 _1.fastq.gz)
  R2=$RAW_DIR/${BASE}_2.fastq.gz
  OUT_R1=$OUT_DIR/trimmed/${BASE}_1.trimmed.fastq.gz
  OUT_R2=$OUT_DIR/trimmed/${BASE}_2.trimmed.fastq.gz
  fastp -i $R1 -I $R2 -o $OUT_R1 -O $OUT_R2 \
        --thread $THREADS --detect_adapter_for_pe \
        --html $OUT_DIR/trimmed/${BASE}_fastp.html --json $OUT_DIR/trimmed/${BASE}_fastp.json
done


# ---- 6. Build BWA index ----
if [ ! -f "${REF}.bwt" ]; then
  echo "📚 Building BWA index..."
  bwa index $REF
fi


# ---- 7. Alignment ----
echo "🎯 Aligning reads..."
for R1 in $OUT_DIR/trimmed/*_1.trimmed.fastq.gz; do
  BASE=$(basename $R1 _1.trimmed.fastq.gz)
  R2=$OUT_DIR/trimmed/${BASE}_2.trimmed.fastq.gz
  SAM=$OUT_DIR/aligned/${BASE}.sam
  BAM=$OUT_DIR/aligned/${BASE}.bam
  SORTED_BAM=$OUT_DIR/aligned/${BASE}_sorted.bam

  bwa mem -t $THREADS $REF $R1 $R2 > $SAM
  samtools view -bS $SAM > $BAM
  samtools sort -@ $THREADS -o $SORTED_BAM $BAM
  samtools index $SORTED_BAM
  rm $SAM $BAM
done


# ---- 8. Counting ----
# ---- 8. Counting ----
COUNT_DIR="analysis_results/counts"
BAM_DIR="analysis_results/aligned"


echo "📊 Running featureCounts..."
mkdir -p "$COUNT_DIR"

# Check for GTF
if [ ! -f "$GTF" ]; then
  echo "⚠️  Annotation file not found: $GTF"
  echo "Skipping featureCounts step."
  exit 0
fi

# Check if there are any BAM files
if [ -z "$(ls -1 $BAM_DIR/*_sorted.bam 2>/dev/null)" ]; then
  echo "❌ No BAM files found in $BAM_DIR"
  exit 1
fi

# Run featureCounts on all sorted BAMs
featureCounts -T 8 -p -F GFF \
  -a "$GTF" \
  -o "$COUNT_DIR/gene_counts.txt" \
  -t gene -g locus_tag \
  $BAM_DIR/*_sorted.bam

# Optional: extract a clean count matrix (for DESeq2 / edgeR)
awk 'NR>2 {printf "%s", $1; for(i=7;i<=NF;i++) printf "\t%s", $i; printf "\n"}' \
  "$COUNT_DIR/gene_counts.txt" > "$COUNT_DIR/gene_counts_matrix.tsv"

echo "✅ FeatureCounts completed successfully!"
echo "📁 Results saved in: $COUNT_DIR/"

