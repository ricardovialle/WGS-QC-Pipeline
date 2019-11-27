#0) Introductions

#snakemake pipeline for QC of vcf files. Created first on 191115.

#1) Set up Variables from Config files
shell.prefix('export PS1="";source activate 191115_vcf_QC_snakemake_env;')
#shell.prefix('export PS1="";source activate bazam-pipeline;')

inFolder = config['inFolder']
outFolder = config['outFolder']
tempFolder = config['tempFolder']
statsFolder = config['statsFolder']

#Makes sure there is no distinction whether you enter /input or /input/
if (inFolder.endswith("/") == False):
    inFolder = inFolder + "/"

if (outFolder.endswith("/") == False):
    outFolder = outFolder + "/"

if (tempFolder.endswith("/") == False):
    tempFolder = tempFolder + "/"

if (statsFolder.endswith("/") == False):
    statsFolder = statsFolder + "/"

print(inFolder)
print(outFolder)
print(tempFolder)
print(statsFolder)

MISS_THRESH_SNP = config['MISS_THRESH_SNP']
ODP = config['ODP']
MQ_MAX = config['MQ_MAX']
MQ_MIN = config['MQ_MIN']
VQSLOD = config['VQSLOD']
GDP = config['GDP']
GQ = config['GQ']
INBREEDING_COEF = config['INBREEDING_COEF']
MISS_THRESH_INDI = config['MISS_THRESH_INDI']
RELATEDNESS_THRESH = config['RELATEDNESS_THRESH']


gzvcf_suffix = config['gzvcf_suffix']

#2) Pull Samples names from inFolder and uses string manipulation to parse their names

#import libraries
import glob
import os
import re
import numpy as np
import itertools as iter

#inFolder="191120_test/input"
#gzvcf_suffix=".vcf.gz"

#Declare alleles variable to establish a later used wildcard
#alleles = ['Biallelic','Triallelic']
alleles = ['Biallelic']

#allFiles finds all gzvcf files in the specific input directory. These names will later be parsed to find matching file sets
allFiles = [x.split(inFolder) for x in glob.glob(inFolder + "/*" + gzvcf_suffix)]
allFiles = [x[1] for x in allFiles]
allFiles = [x.split(gzvcf_suffix) for x in allFiles]
allFiles = [x[0] for x in allFiles]

#Split names in allFiles to find matching file names
#regex = "_chr(?:[1,2][1,2,3,4,5,6,7,8,9,0]|[1,2,3,4,5,6,7,8,9])_"
regex = "_chr(?:[1,2][1,2,3,4,5,6,7,8,9,0]|[1,2,3,4,5,6,7,8,9])\." #regex is a regular expression to find strings such as "_chr1_", "_chr17_", etc.
chr = [re.findall(regex,x) for x in allFiles] #finds specific chromosome for each file. If there is no line matching regex, then returns nothing
valid = np.where([len(x) > 0 for x in chr])[0].tolist() #returns positions in allFiles where there are valid files for QC
allFiles_valid = [allFiles[x] for x in valid] #allFiles valid only takes the files in directory that A) have the gzvcf suffic, and B) have a "_chr#_" string within them. This includes chromosomes 1-22, but excludes X and Y

chr = [re.findall(regex,x) for x in allFiles_valid] #retakes the chr file, but excluding files with chrX and chrY, as well as excluding other files in the input directory not fulfilling criteria

#samples1 is the sample name before "_chr#_" and samples2 is the samples name after
#print(allFiles_valid) #debug
#print(chr) #debug
allFiles_split = [re.split(regex,x) for x in allFiles_valid]
#print(allFiles_split) #debug
samples1 = [x[0] for x in allFiles_split]
samples2 = [x[1] for x in allFiles_split]

#convert samples1 and samples2 to sets to only keep unique values
samples1_set = set(samples1)
samples2_set = set(samples2)

#find indices for all unique values in both samples1 and samples2
samples1_indices = [[i for i, x in enumerate(samples1) if x == y] for y in samples1_set]
samples2_indices = [[i for i, x in enumerate(samples2) if x == y] for y in samples2_set]

#takes all intersections between samples1_indices and samples2_indices to return coordinates for every unique pair
def intersection(lst1, lst2):
    lst3 = [value for value in lst1 if value in lst2]
    return lst3
combos = [intersection(x,y) for x,y in list(iter.product(samples1_indices,samples2_indices))]
combos = [x for x in combos if x != []]

#Makes an easy to access list for wildcards with unique sample IDs and the chromosomes associated with each
samples = []
for i in range(len(combos)):
    temp = []
    temp.append(samples1[combos[i][0]])
    temp.append(samples2[combos[i][0]])
    temp.append([chr[j] for j in combos[i]])
    samples.append(temp)

    #for j in range(len(combos[i])):
    #    if j == 0:
    #        temp_string = str(chr[combos[i][j]][0])
    #    else:
    #        temp_string = temp_string + '%' + str(chr[combos[i][j]][0])
    #temp.append(temp_string)
    #samples.append(temp)
print(samples)

for sample in range(len(samples)):
    #list must be created in each loop for each particular combination of samples

    chrs = [x[0] for x in samples[sample][2]]
    chrs = [x[1:-1] for x in chrs]
    #3) "rule all" is a pseudorule that tells snakemake to make this output for each input
    rule all:
        input:
            expand(outFolder + '{sample1}_chrAll_{sample2}_{allele}_QCFinished.recode.vcf', allele = alleles, sample1 = samples[sample][0], sample2 = samples[sample][1])
            #expand(outFolder + '{sample1}_chrAll_{sample2}_{allele}_QCFinished.recode.vcf', sample = range(len(samples)), allele = alleles, sample1 = samples[sample][0], sample2 = samples[sample][1])
        params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]

    #4) Separate biallelics and triallelics for later on
    #Separate out steps later so bcftools stats can evaluate each filter level

    rule Filter0_separateBiallelics:
        input:
            vcfgz = inFolder + '{sample1}_{chr}.{sample2}' + gzvcf_suffix
        output:
            biallelic_Filter0 = tempFolder + '{sample1}_{chr}.{sample2}' + '_Biallelic_Filter0.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}' + '_Biallelic_Filter0_stats.txt'
        #params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcftools/0.1.15; module load bcftools/1.9;"
            "vcftools --gzvcf {input.vcfgz} --min-alleles 2 --max-alleles 2 --recode --recode-INFO-all --stdout | bgzip -c > {output.biallelic_Filter0};"
            "bcftools stats {output.biallelic_Filter0} > {output.stats};"

    # rule Filter0_separateTriallelics:
    #     input:
    #         vcfgz = inFolder + '{sample1}_{chr}.{sample2}' + gzvcf_suffix
    #     output:
    #         triallelic_Filter0 = outFolder + '{sample1}_chrAll_{sample2}_Triallelic_QCFinished.recode.vcf',
    #         stats = statsFolder + '{sample1}_{chr}.{sample2}' + '_Triallelic_Filter0_stats.txt'
    #     params:
    #         unsplit_file = tempFolder + '{sample1}_{chr}.{sample2}' + '_Triallelic_unsplit.recode.vcf.gz'#,
    #         #sample1 = samples[sample][0],
    #         #sample2 = samples[sample][1]
    #     shell:
    #         "module load vcftools/0.1.15; module load bcftools/1.9;"
    #
    #         #this would be where I say "--max-alleles 3" if we only want to keep triallelics
    #         "vcftools --gzvcf {input.vcfgz} --min-alleles 3 --recode --recode-INFO-all --stdout | bgzip -c > {params.unsplit_file};"
    #
    #         #I might need to make it "-m -". I am unclear on what the doc means. People online just seem to do -m though, but theres a way to combine biallelics into multiallelics
    #         #-m splits multiallelics into multiple lines of biallelics, -Oz means the output will be compressed vcf
    #         "bcftools norm -m - -Oz {params.unsplit_file} -o {output.triallelic_Filter0};"
    #         "bcftools stats {output.triallelic_Filter0} > {output.stats};"

    #5) Keep sites that "PASS" by GATK
    rule Filter1_GATK_PASS:
        input:
            Filter0 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter0.recode.vcf.gz'
        output:
            Filter1 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter1.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter1_stats.txt'
        #params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcftools/0.1.15; module load bcftools/1.9;"
            "vcftools --gzvcf {input.Filter0} --remove-filtered-all --stdout --recode --recode-INFO-all | bgzip -c > {output.Filter1};"
            "tabix -p vcf {output.Filter1};"
            "bcftools stats {output.Filter1} > {output.stats};"

    #6) Filter for genotype level depth (DP) (GDP)
    rule Filter2_GDP:
        input:
            Filter1 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter1.recode.vcf.gz'
        output:
            Filter2 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter2.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter2_stats.txt'
        params:
            GDP_thresh = GDP#,
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcflib/v1.0.0-rc0; module load bcftools/1.9;"
            "vcffilter -g \"DP > {params.GDP_thresh}\" {input.Filter1} | bgzip -c > {output.Filter2};"
            "tabix -p vcf {output.Filter2};"
            "bcftools stats {output.Filter2} > {output.stats};"

    #7) Filter for Genome Quality (GQ)
    rule Filter3_GQ:
        input:
            Filter2 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter2.recode.vcf.gz'
        output:
            Filter3 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter3.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter3_stats.txt'
        params:
            GQ_thresh = GQ#,
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcflib/v1.0.0-rc0; module load bcftools/1.9;"
            "vcffilter -g \"GQ > {params.GQ_thresh}\" {input.Filter2} |bgzip -c > {output.Filter3};"
            "bcftools stats {output.Filter3} > {output.stats};"

    #8) Filter for SNP missingness
    rule Filter4_SNP_Missingess:
        input:
            Filter3 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter3.recode.vcf.gz'
        output:
            Filter4 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter4.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter4_stats.txt'
        params:
            MISS_THRESH_SNP = MISS_THRESH_SNP#,
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcftools/0.1.15; module load bcftools/1.9;"
            "vcftools --gzvcf {input.Filter3} --max-missing {params.MISS_THRESH_SNP} --stdout --recode --recode-INFO-all | bgzip -c > {output.Filter4};"
            "tabix -p vcf {output.Filter4};"
            "bcftools stats {output.Filter4} > {output.stats};"

    #9) Filter for Overall Read Depth (DP) (ODP)
    rule Filter5_ODP:
        input:
            Filter4 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter4.recode.vcf.gz'
        output:
            Filter5 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter5.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter5_stats.txt'
        params:
            ODP_thresh = ODP#,
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcflib/v1.0.0-rc0; module load bcftools/1.9;"
            "vcffilter -f \"DP > {params.ODP_thresh}\" {input.Filter4} | bgzip -c > {output.Filter5};"
            "tabix -p vcf {output.Filter5};"
            "bcftools stats {output.Filter5} > {output.stats};"

    #10) Filter for Mapping Quality (MQ)
    rule Filter6_MQ:
        input:
            Filter5 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter5.recode.vcf.gz'
        output:
            Filter6 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter6.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter6_stats.txt'
        params:
            MQ_MAX_THRESH = MQ_MAX,
            MQ_MIN_THRESH = MQ_MIN#,
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcflib/v1.0.0-rc0; module load bcftools/1.9;"
            "vcffilter -f \"MQ > {params.MQ_MIN_THRESH} & MQ < {params.MQ_MAX_THRESH}\" {input.Filter5} | bgzip -c > {output.Filter6};"
            "bcftools stats {output.Filter6} > {output.stats};"

    #11) Separate out Indel files and SNP files in Biallelic files.
    rule Biallelic_Separate_Indels_and_SNPs:
        input:
            Filter6 = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6.recode.vcf.gz'
        output:
            Filter6_SNPs = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6_SNPs.recode.vcf.gz',
            Filter6_SNPs_stats = statsFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6_SNPs_stats.txt',
            Filter6_Indels = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6_Indels.recode.vcf.gz',
            Filter6_Indels_stats = statsFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6_Indels_stats.txt'
        #params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcftools/0.1.15; module load bcftools/1.9;"

            "vcftools --gzvcf {input.Filter6} --remove-indels --stdout --recode --recode-INFO-all | bgzip -c > {output.Filter6_SNPs};"
            "vcftools --gzvcf {input.Filter6} --keep-only-indels --stdout --recode --recode-INFO-all | bgzip -c > {output.Filter6_Indels};"

            "bcftools stats {output.Filter6_SNPs} > {output.Filter6_SNPs_stats};"
            "bcftools stats {output.Filter6_Indels} > {output.Filter6_Indels_stats};"

    #10) Filter Biallelic SNPs for VQSLOD
    rule Biallelic_SNPs_Filter7_VQSLOD:
        input:
            Filter6_SNPs = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6_SNPs.recode.vcf.gz'
        output:
            Filter7_SNPs = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter7_SNPs.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter7_SNPs_stats.txt'
        params:
            VQSLOD_thresh = VQSLOD#,
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load vcftools/0.1.15; module load bcftools/1.9;"
            "vcftools --gzvcf {input.Filter6_SNPs} --stdout --recode --recode-INFO-all | vcffilter -f \"VQSLOD > {params.VQSLOD_thresh}\" | bgzip -c > {output.Filter7_SNPs};"
            "bcftools stats {output.Filter7_SNPs} > {output.stats};"

    #11) Combine Biallelic Indels and SNPs
    rule Biallelic_Combine_Indels_and_SNPs:
        input:
            Filter7_SNPs = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter7_SNPs.recode.vcf.gz',
            Filter6_Indels = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter6_Indels.recode.vcf.gz'
        output:
            Filter7 = tempFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter7.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_Biallelic_Filter7_stats.txt'
        #params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1]
        shell:
            "module load bcftools/1.9;"
            "bcftools concat {input.Filter6_Indels} {input.Filter7_SNPs} | bcftools sort | bgzip -c > {output.Filter7};"
            "tabix -p vcf {output.Filter7};"
            "bcftools stats {output.Filter7} > {output.stats};"

    #12) Filter via Inbreeding_Coef
    rule Filter8_Inbreeding_Coef:
        input:
            Filter7 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter7.recode.vcf.gz'
        output:
            #Filter8 = tempFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter8.recode.vcf.gz',
            Filter8 = tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter8.recode.vcf.gz',
            stats = statsFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter8_stats.txt'
        params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1],
            INBREEDING_COEF = INBREEDING_COEF
        shell:
            "module load vcflib/v1.0.0-rc0; module load bcftools/1.9;"
            "vcffilter -f \"InbreedingCoeff > {params.INBREEDING_COEF}\" {input.Filter7} |bgzip -c > {output.Filter8};"
            "bcftools stats {output.Filter8} > {output.stats};"

    #13) Combine chromosome files for each sample
    rule Biallelic_Combine_Chromosomes:
        input:
            chr_indi = expand(tempFolder + '{sample1}_{chr}.{sample2}_{allele}_Filter8.recode.vcf.gz',
            chr = chrs, sample1 = samples[sample][0], sample2 = samples[sample][1], allele = alleles)
        output:
            #combine_chr = tempFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter8.recode.vcf.gz',
            combine_chr = outFolder + '{sample1}_chrAll_{sample2}_{allele}_QCFinished.recode.vcf',
            #stats = statsFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter8_stats.txt'
            stats = statsFolder + '{sample1}_chrAll_{sample2}_{allele}_QCFinished_stats.txt'
        params:
            #sample1 = samples[sample][0],
            #sample2 = samples[sample][1],
            #chromosomes = samples[sample][2][][0],
            num_chrs = len(samples[sample][2])
        run:
            shell("module load vcftools/0.1.15; module load bcftools/1.9;")

            shell("concat_string=\'\';")

            for i in range(params.num_chrs):
                chromosome = chr_indi[i]
                shell("do concat_string=$concat_string{chromosome}\' \';")

            shell("vcf-concat $concat_string | gzip > {output.combine_chr}};")
            shell("bcftools stats {output.combine_chr} > {output.stats};")
        # shell:
        #     "module load vcftools/0.1.15; module load bcftools/1.9;"
        #
        #     "concat_string=\'\';"
        #     "for i in $(seq {params.num_chrs});"
        #     "do concat_string=$concat_string{input.chr_indi[i]}\' \';"
        #     "done;"
        #     "vcf-concat $concat_string | gzip > {output.combine_chr}};"
        #     "bcftools stats {output.combine_chr} > {output.stats};"

    # #14) Filter via Sample level Missingness
    # rule Filter9_Sample_Missingness:
    #     input:
    #         Filter8 = tempFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter8.recode.vcf.gz'
    #     output:
    #         Filter9 = tempFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter9.recode.vcf.gz'
    #         stats = statsFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter9_stats.txt'
    #     params:
    #         sample1 = samples[sample][0],
    #         sample2 = samples[sample][1],
    #         MISS_THRESH_INDI = MISS_THRESH_INDI
    #     shell:
    #         "module load vcftools/0.1.15; module load bcftools/1.9;"
    #
    #         "vcftools --gzvcf {input.Filter8} --missing-indv --out chr${i}.gq;"
    #         vcftools –gzvcf chr${i}.gq.vcf.gz --remove-indv sample 13 --stdout --
    #         recode --recode-INFO-all
    #
    # #15) Filter via Relatedness
    # rule Filter10_Relatedness:
    #     input:
    #         Filter9 = tempFolder + '{sample1}_chrAll_{sample2}_{allele}_Filter9.recode.vcf.gz'
    #     output:
    #         Final = tempFolder + '{sample1}_chrAll_{sample2}_{allele}_QCFinished.recode.vcf',
    #         stats = statsFolder + '{sample1}_chrAll_{sample2}_{allele}_QCFinished_stats.txt'
    #     params:
    #         sample1 = samples[sample][0],
    #         sample2 = samples[sample][1],
    #         RELATEDNESS_THRESH = RELATEDNESS_THRESH
    #     shell:
