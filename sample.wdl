version 1.0

import "bam-to-gvcf/gvcf.wdl" as gvcf
import "library.wdl" as libraryWorkflow
import "samplesheet.wdl" as samplesheet
import "tasks/biopet.wdl" as biopet


workflow sample {
    input {
        Sample sample
        String outputDir
        File refFasta
        File refDict
        File refFastaIndex
        File dbsnpVCF
        File dbsnpVCFindex
        Array[File] indexFiles
        File bwaFasta
    }

    scatter (lb in sample.libraries) {
        call libraryWorkflow.library as library {
            input:
                outputDir = outputDir + "/lib_" + lb.id,
                library = lb,
                sampleId = sample.id,
                refFasta = refFasta,
                refDict = refDict,
                refFastaIndex = refFastaIndex,
                dbsnpVCF = dbsnpVCF,
                dbsnpVCFindex = dbsnpVCFindex,
                indexFiles = indexFiles,
                bwaFasta = bwaFasta
        }
    }

    call gvcf.Gvcf as createGvcf {
        input:
            refFasta = refFasta,
            refDict = refDict,
            refFastaIndex = refFastaIndex,
            bamFiles = library.bqsrBamFile,
            bamIndexes = library.bqsrBamIndexFile,
            gvcfPath = outputDir + "/" + sample.id + ".g.vcf.gz",
            dbsnpVCF = dbsnpVCF,
            dbsnpVCFindex = dbsnpVCFindex
    }

    output {
        File gvcf = createGvcf.outputGVCF
        File gvcfIndex = createGvcf.outputGVCFindex
    }
}