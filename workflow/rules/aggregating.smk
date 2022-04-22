################################################################################
## multiQC
## using files instead of directories to ensure all samples qc metircs included
rule multiqc_pe:
    input:
        ## using "samples" to distinguish from wildcard.sample !!!
        get_fastqc_stats(),
        get_dedup_bam_stats(),
        expand("raw_bam/{samples}_sorted.bam.stats.txt",  samples = SAMPLES["sample_id"]),
        expand("dedup_bam_pe/{samples}_insert_size_metrics.txt", samples = SAMPLES["sample_id"]),
    output:
        # "aggregated/QC_se/multiqc_report.html"      ## only works for stand-alone mode,
        "aggregated/QC_pe/{sample}.html"              ## works for --cluster as we
    log:
        "logs/{sample}_pe.log"                        ## wildcard.sample needed for --cluster
    conda:
        "extra_env/multiQC.yaml"
    shell:
        "(multiqc {input} -o aggregated/QC_pe/) 2> {log}"


## single end
rule multiqc_se:
    input:
        ## using "samples" to distinguish from wildcard.sample !!!
        get_fastqc_stats(),
        get_dedup_bam_stats(),
        expand("raw_bam/{samples}_sorted.bam.stats.txt",  samples = SAMPLES["sample_id"]),
    output:
        "aggregated/QC_se/{sample}.html"
    log:
        "logs/{sample}_se.log"
    conda:
        "extra_env/multiQC.yaml"
    shell:
        "(multiqc {input} -o aggregated/QC_se/) 2> {log}"


##############################
## Aggregating meth QC reports
rule aggregate_meth_qc:
    input:
        ## using "samples" to distinguish from wildcard.sample !!!
        expand("meth_qc_quant/{samples}_meth_qc.txt", samples = SAMPLES["sample_id"])
    output:
        "aggregated/{sample}.txt"
    shell:
        "head -n 1 {input[0]} > {output} && "
        "cat {input} | sed '1~2d' >> {output}"


##########################################
## Aggregating meth Quantification outputs
## bin_id used to save storage space
rule aggregate_meth_quant:
    input:
        ## using "samples" to distinguish from wildcard.sample !!!
        bin  = expand("meth_qc_quant/{samples}_Granges_CpGs.bed", samples = SAMPLES["sample_id"][0]),
        cnt = expand("meth_qc_quant/{samples}_count.txt", samples = SAMPLES["sample_id"]),
        rpkm  = expand("meth_qc_quant/{samples}_rpkm.txt", samples = SAMPLES["sample_id"]),
        CNV_qsea   = expand("meth_qc_quant/{samples}_CNV_qsea.txt", samples = SAMPLES["sample_id"]),
        beta_qsea  = expand("meth_qc_quant/{samples}_beta_qsea.txt", samples = SAMPLES["sample_id"]),
        nrpm_qsea  = expand("meth_qc_quant/{samples}_nrpm_qsea.txt", samples = SAMPLES["sample_id"]),
        rms_medips = expand("meth_qc_quant/{samples}_rms_medips.txt", samples = SAMPLES["sample_id"]),
        rms_medestrand  = expand("meth_qc_quant/{samples}_rms_medestrand.txt", samples = SAMPLES["sample_id"]),
        logitbeta_qsea  = expand("meth_qc_quant/{samples}_logitbeta_qsea.txt", samples = SAMPLES["sample_id"]),
    output:
        bin  = "aggregated/{sample}_bin.bed",
        cnt  = "aggregated/{sample}_count.txt.gz",
        rpkm  = "aggregated/{sample}_rpkm.txt.gz",
        CNV_qsea   = "aggregated/{sample}_CNV_qsea.txt.gz",
        beta_qsea  = "aggregated/{sample}_beta_qsea.txt.gz",
        nrpm_qsea  = "aggregated/{sample}_nrpm_qsea.txt.gz",
        rms_medips = "aggregated/{sample}_rms_medips.txt.gz",
        rms_medestrand  = "aggregated/{sample}_rms_medestrand.txt.gz",
        logitbeta_qsea  = "aggregated/{sample}_logitbeta_qsea.txt.gz"
    log:
        "logs/{sample}_quant_aggregate.log"
    resources:
        mem_mb=60000
    shell:
        "(cp {input.bin}  {output.bin} && "
        "paste {output.bin} {input.cnt}  | bgzip > {output.cnt} && tabix -p bed {output.cnt} && "
        "paste {output.bin} {input.rpkm} | bgzip > {output.rpkm} && tabix -p bed {output.rpkm} && "
        "paste {output.bin} {input.CNV_qsea}   |  bgzip > {output.CNV_qsea} && tabix -p bed {output.CNV_qsea} && "
        "paste {output.bin} {input.beta_qsea}  |  bgzip > {output.beta_qsea} && tabix -p bed {output.beta_qsea} && "
        "paste {output.bin} {input.nrpm_qsea}  |  bgzip > {output.nrpm_qsea} && tabix -p bed {output.nrpm_qsea} && "
        "paste {output.bin} {input.rms_medips} |  bgzip > {output.rms_medips} && tabix -p bed {output.rms_medips} && "
        "paste {output.bin} {input.rms_medestrand} | bgzip > {output.rms_medestrand} && tabix -p bed {output.rms_medestrand} && "
        "paste {output.bin} {input.logitbeta_qsea} | bgzip > {output.logitbeta_qsea} && tabix -p bed {output.logitbeta_qsea})  2> {log}"


########################################################
## filter out chrX, chrY, chrM and ENCODE blacklist bins
## autos_bfilt: autosomes + blacklist fitered
rule meth_bin_filter:
    input:
        bin = "aggregated/{sample}_bin.bed"
    output:
        "autos_bfilt/{sample}_autos_bfilt_bin.bed",
        "autos_bfilt/{sample}_autos_bfilt_bin_merged.bed"
    conda:
        "extra_env/bedtools.yaml"
    params:
        blacklist
    shell:
        ## autosomes
        "head -1 {input.bin} > autos_bfilt/tmp_header.bed && "
        "grep -v 'chrM\|chrX\|chrY' {input.bin}  >  autos_bfilt/tmp_1.bed && "
        ## mask blacklist
        "intersectBed -a autos_bfilt/tmp_1.bed -b {params} -v >  autos_bfilt/tmp_2.bed && "
        "sort -k4,4n autos_bfilt/tmp_2.bed > autos_bfilt/tmp_3.bed && "
        "cat autos_bfilt/tmp_header.bed  autos_bfilt/tmp_3.bed > {output[0]} && "

        ## merge filtered bins for tabix
        "bedtools merge -i {output[0]} -d 1 | sort -V -k1,1 -k2,2n > {output[1]} && "
        "rm autos_bfilt/tmp_*.bed "


#################################################################################
## meth quantification after filtering chrX, chrY, chrM and ENCODE blacklist bins
rule meth_quant_filter:
    input:
        bin = "autos_bfilt/{sample}_autos_bfilt_bin_merged.bed",
        cnt = "aggregated/{sample}_count.txt.gz",
        rpkm  = "aggregated/{sample}_rpkm.txt.gz",
        CNV_qsea   = "aggregated/{sample}_CNV_qsea.txt.gz",
        beta_qsea  = "aggregated/{sample}_beta_qsea.txt.gz",
        nrpm_qsea  = "aggregated/{sample}_nrpm_qsea.txt.gz",
        rms_medips = "aggregated/{sample}_rms_medips.txt.gz",
        rms_medestrand  = "aggregated/{sample}_rms_medestrand.txt.gz",
        logitbeta_qsea  = "aggregated/{sample}_logitbeta_qsea.txt.gz",
    output:
        cnt = "autos_bfilt/{sample}_count_autos_bfilt.txt.gz",
        rpkm  = "autos_bfilt/{sample}_rpkm_autos_bfilt.txt.gz",
        CNV_qsea   = "autos_bfilt/{sample}_CNV_qsea_autos_bfilt.txt.gz",
        beta_qsea  = "autos_bfilt/{sample}_beta_qsea_autos_bfilt.txt.gz",
        nrpm_qsea  = "autos_bfilt/{sample}_nrpm_qsea_autos_bfilt.txt.gz",
        rms_medips = "autos_bfilt/{sample}_rms_medips_autos_bfilt.txt.gz",
        rms_medestrand  = "autos_bfilt/{sample}_rms_medestrand_autos_bfilt.txt.gz",
        logitbeta_qsea  = "autos_bfilt/{sample}_logitbeta_qsea_autos_bfilt.txt.gz"
    resources:
        mem_mb=60000
    shell:
        "tabix -p bed -R {input.bin} -h {input.cnt} | bgzip > {output.cnt} && tabix -p bed {output.cnt} && "
        "tabix -p bed -R {input.bin} -h {input.rpkm} | bgzip > {output.rpkm} && tabix -p bed {output.rpkm} && "
        "tabix -p bed -R {input.bin} -h {input.CNV_qsea}   |  bgzip > {output.CNV_qsea} && tabix -p bed {output.CNV_qsea} && "
        "tabix -p bed -R {input.bin} -h {input.beta_qsea}  |  bgzip > {output.beta_qsea} && tabix -p bed {output.beta_qsea} && "
        "tabix -p bed -R {input.bin} -h {input.nrpm_qsea}  |  bgzip > {output.nrpm_qsea} && tabix -p bed {output.nrpm_qsea} && "
        "tabix -p bed -R {input.bin} -h {input.rms_medips} |  bgzip > {output.rms_medips} && tabix -p bed {output.rms_medips} && "
        "tabix -p bed -R {input.bin} -h {input.rms_medestrand} | bgzip > {output.rms_medestrand} && tabix -p bed {output.rms_medestrand} && "
        "tabix -p bed -R {input.bin} -h {input.logitbeta_qsea} | bgzip > {output.logitbeta_qsea} && tabix -p bed {output.logitbeta_qsea}"
