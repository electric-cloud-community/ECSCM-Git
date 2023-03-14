package com.cloudbees.plugin.spec
import com.electriccloud.plugin.spec.*
import com.cloudbees.plugin.spec.*
import com.electriccloud.plugins.annotations.*
import spock.lang.*
import com.electriccloud.spec.*
import groovy.json.JsonSlurper
import groovyx.net.http.HTTPBuilder
import static groovyx.net.http.ContentType.JSON
import static groovyx.net.http.Method.POST
import com.cloudbees.plugin.spec.DataSource.WebhookBitbucketDS as ds

class WebhookBitbucketSuite extends PluginTestHelper {
    static String projectName = "Specs Tests: ${pluginName}-WebhookBitbucket"
    static String configName = "${projectName}-Config"
    static String resourceName = 'local'
    static String serviceAccountName = 'specs-webhook-bitbucket'
    static String pipelineName = 'Specs Webhook Bitbucket'
    static String scheduleName = 'PipelineSchedule'

    @Shared
    def http = null

    @Shared
    def webhookData = [commit: 'test']
    @Shared
    def searchParams = [
        ec_webhookRepositoryName: 'pluginsdev/specs-test-repo',
        ec_webhookEventType: 'push',
        ec_webhookEventSource: 'bitbucket',
        ec_webhookBranch: 'testbranch'
    ]

    @Shared
    def sessionId = null

    @Shared
    def TCs = [
        C000001: [ ids: 'C000001', description: 'Only required parameters.'],
        C000002: [ ids: 'C000002', description: 'All parameters.'],
    ]

    def doSetupSpec() {
        def flowHost = "https://$WEBHOOK_FLOW_SERVER"
        println "CloudBees CD server for webhook connection: $flowHost"
        http = new HTTPBuilder(flowHost)
        assert http

        createConfiguration(configName)
        
        def pipelineParams = [
            pipelineName: pipelineName,
            projectName: projectName
        ]

        importProject(projectName, 'dsl/PrepareWebhookBitbucket-pipeline.dsl', pipelineParams)

        def prepareParams = [
            accountName : serviceAccountName,
            pipelineName: pipelineName,
            projectName : projectName
        ]

        def result = dslFile 'dsl/PrepareWebhookBitbucket.dsl', prepareParams
        sessionId = result.session.sessionId
        assert sessionId

        def triggerParams = [
            projectName  : projectName,
            pipelineName : pipelineName,
            releaseName  : null,
            procedureName: null,
            scheduleName : scheduleName,
            triggerName  : null,
            scmConfig: configName,
            searchParams: searchParams
        ]

        importProject(projectName, 'dsl/PrepareWebhookBitbucket-trigger.dsl', triggerParams)

        http.ignoreSSLIssues()
    }

    def doCleanupSpec() {
        conditionallyDeleteProject(projectName)
    }

    @Sanity
    @Unroll
    def "#caseID.ids #caseID.description WebHook Bitbucket Sanity"() {
        given:
        def expectedOutcome = ds.expectedOutcome.success
        when:
        InputStream stream = this.class.getClassLoader().getResourceAsStream(payloadPath)
        assert stream, "$payloadPath not found"
        def payload = stream.text
        //println "PAYLOAD: $payload"

        def (resp, json) = http.request(POST, JSON) { req ->
            uri.path = '/commander/link/webhookServerRequest'
            uri.query = [operationId: 'githubWebhook', pluginConfigName: configName, sessionId: sessionId]            
            body = payload
            headers.'Content-Type' = 'application/json'
            headers.'User-Agent' = 'Bitbucket-Webhooks/2.0'
            headers.'X-Event-Key' = 'repo:push'
            response.success = { resp, json ->
                println 'Webhook request was successful.'
                //println json
                return [resp, json]
            }

            response.failure = { resp ->
                println 'HTTP POST Request failed'
                def outputStream = new ByteArrayOutputStream()
                resp.entity.writeTo(outputStream)
                println outputStream.toString('utf8')
                return [resp, null]
            }
        }
        assert resp.status < 400
        assert json.responses.size == 1
        assert json.responses[0]['value']
        def responseValue = json.responses[0]['value']
        // parse response value json
        def responseValueJson = new JsonSlurper().parseText(responseValue)
        assert responseValueJson instanceof Map
        assert responseValueJson.code == 200
        assert responseValueJson.payload
        def decodedResponsePayload = new String(responseValueJson.payload.decodeBase64())
        println "DECODED RESPONSE PAYLOAD: $decodedResponsePayload"
        def (webhookJobId) = decodedResponsePayload =~ /(?<=job id is )[A-Za-z0-9-]+/
        println "WEBHOOK JOB ID: $webhookJobId"
        println getJobLink(webhookJobId)
        waitUntil {
            jobCompleted webhookJobId
        }
        assert jobStatus(webhookJobId).outcome == 'success'
        def logs = getJobLogs(webhookJobId)
        then:
        assert resp.status < 400
        assert logs =~ /Launched pipeline from the schedule $projectName:$scheduleName/
        where:
        caseID      | payloadPath            | ec_runDuplicates           | ec_quietTime           | ec_maxRetries
        TCs.C000001 | ds.payloadPath.correct | ''                         | ''                     | ''
        TCs.C000002 | ds.payloadPath.correct | ds.ecRunDuplicates.correct | ds.ecQuietTime.correct | ds.ecMaxRetries.correct
    }
}
