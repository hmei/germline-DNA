version 1.0

import "jointgenotyping/jointgenotyping.wdl" as jointgenotyping
import "sample.wdl" as sampleWorkflow
import "samplesheet.wdl" as samplesheet
import "tasks/biopet.wdl" as biopet

workflow pipeline {
    input {
        Array[File] sampleConfigFiles
        String outputDir
        File refFasta
        File refDict
        File refFastaIndex
        File dbsnpVCF
        File dbsnpVCFindex
        Array[File] indexFiles
        File bwaFasta
    }

    call biopet.ValidateVcf as validateVcf {
        input:
            vcfFile = dbsnpVCF,
            vcfIndex = dbsnpVCFindex,
            refFasta = refFasta,
            refFastaIndex = refFastaIndex,
            refDict = refDict
    }

    # Parse sample configs
    scatter (sampleConfigFile in sampleConfigFiles) {
        call samplesheet.SampleConfigFileToStruct as config {
            input:
                sampleConfigFile = sampleConfigFile
        }
    }

    Array[Sample] samples = flatten(config.samples)

    # Running sample subworkflow
    scatter (sm in samples) {
        call sampleWorkflow.sample as sample {
            input:
                outputDir = outputDir + "/samples/" + sm.id,
                sample = sm,
                refFasta = refFasta,
                refDict = refDict,
                refFastaIndex = refFastaIndex,
                dbsnpVCF = dbsnpVCF,
                dbsnpVCFindex = dbsnpVCFindex,
                indexFiles = indexFiles,
                bwaFasta = bwaFasta
        }
    }

    call jointgenotyping.JointGenotyping {
        input:
            refFasta = refFasta,
            refDict = refDict,
            refFastaIndex = refFastaIndex,
            outputDir = outputDir,
            gvcfFiles = sample.gvcf,
            gvcfIndexes = sample.gvcfIndex,
            vcfBasename = "multisample",
            dbsnpVCF = dbsnpVCF,
            dbsnpVCFindex = dbsnpVCFindex
    }

    output {
    }
}