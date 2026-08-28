// workflow to upload results to PanoramaWeb

// modules
include { UPLOAD_FILE } from "../modules/panorama"
include { IMPORT_SKYLINE } from "../modules/panorama"

// Write a record of every file this run uploads and where it went, to
// <result_dir>/panorama/panorama_uploads.tsv. This is the companion to file_checksums.tsv:
// without it nothing says what was sent to Panorama after the fact. It is also the only way
// to check upload routing in a stub run, where the upload command itself never executes.
def write_upload_manifest(upload_ch) {
    return upload_ch
        .map{ path, url -> "${file(path).name}\t${url}" }
        .collectFile(name: 'panorama_uploads.tsv',
                     storeDir: params.output_directories.panorama,
                     seed: 'file\tdestination',
                     sort: true, newLine: true)
}

workflow panorama_upload_results {

    take:
        webdav_url
        all_search_file_ch
        search_engine
        final_skyline_file
        mzml_file_ch
        input_file_ch           // everything needed to reproduce the run; see main.nf
        nextflow_config_file
        nextflow_run_details
        output_file_hashes
        skyline_report_ch
        use_batch_mode
        aws_secret_id

    main:

        if(!webdav_url.endsWith("/")) {
            webdav_url += "/"
        }

        upload_webdav_url = webdav_url + getUploadDirectory()

        mzml_file_ch.map { batch, path ->
                tuple(path, upload_webdav_url + "/results/msconvert${use_batch_mode == true ? '/' + batch : ''}")
            }.concat(nextflow_run_details.map { path -> tuple(path, upload_webdav_url) })
            .concat(output_file_hashes.map { path -> tuple(path, upload_webdav_url) })
            .concat(Channel.fromPath(nextflow_config_file).map { path -> tuple(path, upload_webdav_url) })
            .concat(input_file_ch.map { path -> tuple(path, upload_webdav_url + "/input-files") })
            .concat(all_search_file_ch.map { path -> tuple(path, upload_webdav_url + "/results/${search_engine}") })
            .concat(final_skyline_file.map { path -> tuple(path, upload_webdav_url + "/results/skyline") })
            .concat(skyline_report_ch.map { path -> tuple(path, upload_webdav_url + "/results/skyline_reports") })
            .set { all_file_upload_ch }

        upload_manifest = write_upload_manifest(all_file_upload_ch)

        UPLOAD_FILE(all_file_upload_ch, aws_secret_id)

        // will be used for state dependency -- pass this channel into any process that requires
        // all file uploads to be complete
        uploads_finished = UPLOAD_FILE.out.stdout
            .collect()
            .map { true }  // will only contain a single true value after all uploads are finished
                           // passing uploads_finished into a subsequent process will ensure that
                           // process will only run after all uploads are finished.

        // import Skyline document if requested
        if(params.panorama.import_skyline) {
            final_skyline_doc_name = final_skyline_file.map{ it -> it.name }
            IMPORT_SKYLINE(
                uploads_finished,
                final_skyline_doc_name,
                upload_webdav_url + "/results/skyline",
                aws_secret_id
            )
        }

    emit:
        uploads_finished
        upload_manifest
}

workflow panorama_upload_mzmls {

    take:
        webdav_url
        mzml_file_ch
        nextflow_run_details
        nextflow_config_file
        aws_secret_id

    main:

        if(!webdav_url.endsWith("/")) {
            webdav_url += "/"
        }

        upload_webdav_url = webdav_url + getUploadDirectory()

        mzml_file_ch.map { path -> tuple(path, upload_webdav_url + "/results/msconvert") }
            .concat(nextflow_run_details.map { path -> tuple(path, upload_webdav_url) })
            .concat(Channel.fromPath(nextflow_config_file).map { path -> tuple(path, upload_webdav_url) })
            .set { all_file_upload_ch }

        upload_manifest = write_upload_manifest(all_file_upload_ch)

        UPLOAD_FILE(all_file_upload_ch, aws_secret_id)

    emit:
        upload_manifest
}

def getUploadDirectory() {
    return "nextflow/${getCurrentTimestamp()}/${workflow.sessionId}"
}

def getCurrentTimestamp() {
    java.time.LocalDateTime now = java.time.LocalDateTime.now()
    java.time.format.DateTimeFormatter formatter = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH-mm-ss")
    return now.format(formatter)
}
