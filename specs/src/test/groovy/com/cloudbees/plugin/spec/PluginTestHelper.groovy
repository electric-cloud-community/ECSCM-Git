package com.cloudbees.plugin.spec

import com.electriccloud.spec.PluginSpockTestSupport

class PluginTestHelper extends PluginSpockTestSupport {
    static final String pluginName = 'ECSCM-Git'
    static def configId = 1

    static def tmpDir = System.getProperty('java.io.tmpdir')
    def final static slash = (isWin()) ? "\\" : "/"

    static def AUTOMATION_TESTS_CONTEXT_RUN = System.getenv('AUTOMATION_TESTS_CONTEXT_RUN') ?: 'Sanity,Regression,E2E'

    static def PLUGIN_NAME = System.getenv('PLUGIN_NAME') ?: 'ECSCM-Git'
    static def PLUGIN_VERSION = System.getenv('PLUGIN_VERSION') ?: '3.11.1'

    static def GIT_USERNAME = System.getenv('GIT_USERNAME')
    static def GIT_PASSWORD = System.getenv('GIT_PASSWORD')
    static def GIT_AGENT_HOST = System.getenv('GIT_AGENT_HOST')?: 'git'
    static def GIT_AGENT_PORT = System.getenv('GIT_AGENT_PORT')?: '7808'
    static def COMMANDER_SERVER = System.getenv('COMMANDER_SERVER') ?: 'electricflow'
    static def WEBHOOK_FLOW_SERVER = System.getenv('WEBHOOK_FLOW_SERVER') ?: 'localhost'
    static String CONFIG_NAME = 'specConfig'

    def static isWin() {
        return System.properties['os.name'].toLowerCase().contains("windows")
    }

    def static getResourceOS(def resourceName = 'local') {
        def pingResult
        assert resourceName
        try {
            pingResult = dsl """
                pingResource(resourceName: $resourceName)
            """
        } catch (Throwable e) {
            logger.debug("Can't ping resource: ${resourceName}")
        }

        def resource
        try {
            resource = dsl """
                getResource(resourceName: $resourceName)
            """
        } catch (Throwable e) {
            logger.debug("Can't get resource: ${resourceName}")
        }

        return resource
    }

    def static getTmpDir() {
        if (getResourceOS() == "Windows") {
            return ""
        } else {
            return "/tmp"
        }
    }

    def createSCMConfig(configName, userName, password) {
        def credentials = [
            [credentialName: 'credential', userName: userName, password: password],
            [credentialName: 'webhookSecret', userName: '', password: '']
        ]

        def exists = dsl ("getProperty propertyName: '/plugins/ECSCM/project/scm_cfgs/$configName'")?.property
        if (exists) {
            return
        }

        def result = runProcedure('/plugins/ECSCM-Git/project',
            'CreateConfiguration',
            [
                config        : configName,
                desc          : 'Automation Test configuration for Git',
                webhookSecret : 'webhookSecret',
                credential    : 'credential',
                credentialType: 'password'
            ],
            credentials
        )

        assert result.outcome == 'success'
    }

    def createConfiguration(String configName = CONFIG_NAME, Map props = [:]) {

        if (System.getenv('RECREATE_CONFIG')) {
            props.recreate = true
        }

        createSCMConfig(configName, GIT_USERNAME, GIT_PASSWORD)
    }

    def deleteSCMConfiguration(def configName = CONFIG_NAME) {
        def result = runProcedure('/plugins/ECSCM/project', 'DeleteConfiguration', [
                config: configName
        ])
        assert result.outcome == 'success'
        logger.debug("SCM Configuration deleted, Configuration Name:  ${configName}")
        println "SCM Configuration deleted, Configuration Name:  ${configName}"
    }

    def getStepSummary(def jobId, def stepName) {
        assert jobId
        def summary
        def property = "/myJob/jobSteps/RunProcedure/steps/$stepName/summary"
        try {
            summary = getJobProperty(property, jobId)
        } catch (Throwable e) {
            logger.debug("Can't retrieve Upper Step Summary from the property: '$property'; check job: " + jobId)
        }
        return summary
    }

    def cleanupDirOnResource(def projectName, def resource, def dirPath, def recursive = 1) {
        def procedureName = 'DeleteDirectory'
        def params = [
                Path: '',
                Recursive: '',
        ]
        dslFile "dsl/EC-FileOps-procedure.dsl", [projectName: projectName, resourceName: resource, procedureName: procedureName, params: params]
        def runParameters = [
                Path: dirPath,
                Recursive: recursive,
        ]
        def result = runProcedure(projectName, procedureName, runParameters, [], resource)
       // assert result.outcome == 'success'
    }

    def createGitResource() {
        def host = GIT_AGENT_HOST
        def resources = dsl "getResources()"
        logger.debug(objectToJson(resources))

        def resource = resources.resource.find {
            it.hostName == host || it.resourceName == host
        }
        if (resource) {
            logger.debug("Git resource already exists")
            return resource.resourceName
        }

        def workspaceName = randomize(GIT_AGENT_HOST)
        def workspaceResult = dsl """
try {
            createWorkspace(
                workspaceName: '${workspaceName}',
                agentDrivePath: '/tmp',
                agentUncPath: '/tmp',
                agentUnixPath: '/tmp',
                local: '1'
            )
} catch (Exception e) {}
        """
        logger.debug(objectToJson(workspaceResult))

        def result = dsl """
            createResource(
                resourceName: '$GIT_AGENT_HOST',
                hostName: '$host',
                port: '$GIT_AGENT_PORT',
                workspaceName: '$workspaceName'
            )
        """

        logger.debug(objectToJson(result))
        def resName = result?.resource?.resourceName
        assert resName
        resName
    }

}
