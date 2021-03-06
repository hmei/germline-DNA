version 1.0

# Copyright (c) 2018 Leiden University Medical Center
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import "sample.wdl" as sampleWorkflow
import "gatk-variantcalling/gatk-variantcalling.wdl" as gatkVariantWorkflow
import "structs.wdl" as structs
import "tasks/biowdl.wdl" as biowdl
import "tasks/common.wdl" as common
import "tasks/multiqc.wdl" as multiqc
import "tasks/vt.wdl" as vt
import "tasks/samtools.wdl" as samtools

workflow Germline {
    input {
        File sampleConfigFile
        String outputDir = "."
        File referenceFasta
        File referenceFastaFai
        File referenceFastaDict
        BwaIndex bwaIndex
        File dockerImagesFile
        File dbsnpVCF
        File dbsnpVCFIndex
        File? regions
        File? XNonParRegions
        File? YNonParRegions
        Boolean normalizedVcf = false
        # Only run multiQC if the user specified an outputDir
        Boolean runMultiQC = if (outputDir == ".") then false else true
    }

    String genotypingDir = outputDir + "/multisample_variants/"

    # Parse docker Tags configuration and sample sheet
    call common.YamlToJson as ConvertDockerImagesFile {
        input:
            yaml = dockerImagesFile
    }
    Map[String, String] dockerImages = read_json(ConvertDockerImagesFile.json)

    call biowdl.InputConverter as ConvertSampleConfig {
        input:
            samplesheet = sampleConfigFile,
            dockerImage = dockerImages["biowdl-input-converter"]
    }
    SampleConfig sampleConfig = read_json(ConvertSampleConfig.json)


    # Running sample subworkflow
    scatter (samp in sampleConfig.samples) {
        call sampleWorkflow.Sample as sample {
            input:
                sampleDir = outputDir + "/samples/" + samp.id,
                sample = samp,
                referenceFasta = referenceFasta,
                referenceFastaFai = referenceFastaFai,
                referenceFastaDict = referenceFastaDict,
                bwaIndex = bwaIndex,
                dbsnpVCF = dbsnpVCF,
                dbsnpVCFIndex = dbsnpVCFIndex,
                dockerImages = dockerImages
        }
        BamAndGender bamfilesAndGenders = object {file: sample.recalibratedBam,
                                                  index: sample.recalibratedBamIndex,
                                                  gender: samp.gender}
    }

    call gatkVariantWorkflow.GatkVariantCalling as variantcalling {
        input:
            bamFilesAndGenders = bamfilesAndGenders,
            referenceFasta = referenceFasta,
            referenceFastaFai = referenceFastaFai,
            referenceFastaDict = referenceFastaDict,
            dbsnpVCF = dbsnpVCF,
            dbsnpVCFIndex = dbsnpVCFIndex,
            XNonParRegions = XNonParRegions,
            YNonParRegions = YNonParRegions,
            regions = regions,
            outputDir = genotypingDir,
            vcfBasename = "multisample",
            dockerImages = dockerImages,
    }

    if (normalizedVcf) {
        String vcfBasename = "multisample"
        call vt.Normalize as normalize {
            input:
                inputVCF = select_first([variantcalling.outputVcf]),
                inputVCFIndex = select_first([variantcalling.outputVcfIndex]),
                referenceFasta = referenceFasta,
                referenceFastaFai = referenceFastaFai,
                outputPath = outputDir + "/" + vcfBasename + ".normalized_decomposed.vcf.gz",
        }

        call samtools.Tabix as tabix {
            input:
                inputFile = normalize.outputVcf,
                outputFilePath = outputDir + "/" + vcfBasename + ".normalized_decomposed.indexed.vcf.gz"
        }
    }

    if (runMultiQC) {
        call multiqc.MultiQC as multiqcTask {
            input:
                # Multiqc will only run if these files are created.
                dependencies = select_all([variantcalling.outputVcfIndex]),
                outDir = outputDir + "/multiqc",
                analysisDirectory = outputDir,
                dockerImage = dockerImages["multiqc"]
        }
    }

    output {
        File multiSampleVcf = select_first([variantcalling.outputVcf])
        File multisampleVcfIndex = select_first([variantcalling.outputVcfIndex])
        File? normalizedMultisampleVcf = tabix.indexedFile
        File? normalizedMultisampleVcfIndex = tabix.index
        Array[File] recalibratedBams = sample.recalibratedBam
        Array[File] recalibratedBamIndexes = sample.recalibratedBamIndex
        Array[File] markdupBams = sample.markdupBam
        Array[File] markudpBamIndexex = sample.markdupBamIndex
        Array[File] bamMetricsFiles = flatten(sample.metricsFiles)
    }

    parameter_meta {
        sampleConfigFile: {description: "The samplesheet, including sample ids, library ids, readgroup ids and fastq file locations.",
                           category: "required"}
        outputDir: {description: "The directory the output should be written to.", category: "common"}
        referenceFasta: { description: "The reference fasta file", category: "required" }
        referenceFastaFai: { description: "Fasta index (.fai) file of the reference", category: "required" }
        referenceFastaDict: { description: "Sequence dictionary (.dict) file of the reference", category: "required" }
        dbsnpVCF: { description: "dbsnp VCF file used for checking known sites", category: "required"}
        dbsnpVCFIndex: { description: "Index (.tbi) file for the dbsnp VCF", category: "required"}
        bwaIndex: {description: "The BWA index files.", category: "required"}
        dockerImagesFile: {description: "A YAML file describing the docker image used for the tasks. The dockerImages.yml provided with the pipeline is recommended.",
                           category: "advanced"}
        regions: {description: "A bed file describing the regions to call variants for.", category: "common"}
        runMultiQC: {description: "Whether or not MultiQC should be run.", category: "advanced"}
        normalizedVcf: {description: "Normalize the multisample.", category: "common"}
        XNonParRegions: {description: "Bed file with the non-PAR regions of X.", category: "common"}
        YNonParRegions: {description: "Bed file with the non-PAR regions of Y.", category: "common"}

    }
}