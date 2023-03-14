package com.cloudbees.plugin.spec


import com.electriccloud.plugins.annotations.Sanity
import spock.lang.*
import com.cloudbees.plugin.spec.dataSource.CCParameters

@Stepwise
class CheckoutCode extends PluginTestHelper {
    static final String projectName = "Spec Tests: Checkout code"

    static final String subProcedureCheckoutCode      = "CheckoutCode"
    static final String procedureCheckoutCodeOneStep  = "CheckoutCode One Step"
    static final String procedureCheckoutCodeTwoSteps  = "CheckoutCode Two Steps"

    static resultPropertyBase = '/myJob/'

    static final timeOut = 180

    @Shared
    def config

    @Shared
    def resName

    @Shared
    def checkoutCodeOneStepParams = [
        config             : '',
        dest               : 'dest_dir',
        commit             : '',
        GitBranch          : 'master',
        clone              : '',
        overwrite          : '',
        depth              : '',
        tag                : '',
        GitRepo            : '''https://github.com/git/git.git
https://github.com/vim/vim.git'''
    ]

    @Shared
    def checkoutCodeTwoStepsParams = [
        config             : '',
        dest_0             : 'dest_dir_0',
        dest_1             : 'dest_dir_1',
        commit             : '',
        GitBranch_0        : 'next',
        GitBranch_1        : 'master',
        clone              : '',
        overwrite          : '',
        depth              : '',
        tag                : '',
        GitRepo_0          : 'https://github.com/git/git.git',
        GitRepo_1          : 'https://github.com/vim/vim.git'
    ]

    @Shared
    String caseId

    def doSetupSpec() {
        resName = createGitResource()

        config = CCParameters.configurationName.sanity + configId.toString()
        configId ++
        createSCMConfig(config, GIT_USERNAME, GIT_PASSWORD)

        logger.debug('#000: '+config)

        dslFile "dsl/RunProcedureOneStep.dsl", [
            projectName     : projectName,
            procedureName   : procedureCheckoutCodeOneStep,
            subProcedureName: subProcedureCheckoutCode,
            resName         : resName,
            params          : checkoutCodeOneStepParams
        ]

        dslFile "dsl/RunProcedureTwoSteps.dsl", [
            projectName     : projectName,
            procedureName   : procedureCheckoutCodeTwoSteps,
            subProcedureName: subProcedureCheckoutCode,
            resName         : resName,
            params          : checkoutCodeTwoStepsParams
        ]
    }

    def doCleanupSpec() {
        deleteSCMConfiguration(config)
        conditionallyDeleteProject(projectName)
    }

    @Sanity
    @Unroll
    def '#caseId: CheckoutCode One Step'() {
        given:
        checkoutCodeOneStepParams.clone = clone
        checkoutCodeOneStepParams.overwrite = overwrite
        checkoutCodeOneStepParams.config = config
        logger.debug('#001: '+checkoutCodeOneStepParams)

        when:
        def result = runProcedure(projectName, procedureCheckoutCodeOneStep, checkoutCodeOneStepParams, [], resName, timeOut)

        then:
        logger.debug('#002: '+getJobLink(result.jobId))
        logger.debug('#003: '+result)
        assert result.outcome == 'success'

        // Get result property
        def properties = getJobProperties(result.jobId)
        logger.debug('#004: '+objectToJson(properties))

        where:
        caseId            | clone | overwrite
        'clone keep'      | '1'   | '0'
        'clone overwrite' | '1'   | '1'
        'pull keep'       | '0'   | '0'
        'pull overwrite'  | '0'   | '1'
    }

    @Sanity
    @Unroll
    def '#caseId: CheckoutCode Two Steps'() {
        given:
        checkoutCodeTwoStepsParams.clone = clone
        checkoutCodeTwoStepsParams.overwrite = overwrite
        checkoutCodeTwoStepsParams.config = config
        logger.debug('#005: '+checkoutCodeTwoStepsParams)

        when:
        def result = runProcedure(projectName, procedureCheckoutCodeTwoSteps, checkoutCodeTwoStepsParams, [], resName, timeOut)

        then:
        logger.debug('#006: '+getJobLink(result.jobId))
        logger.debug('#007: '+result)
        assert result.outcome == 'success'

        // Get result property
        def properties = getJobProperties(result.jobId)
        logger.debug('#008: '+objectToJson(properties))

        where:
        caseId            | clone | overwrite
        'clone keep'      | '1'   | '0'
        'clone overwrite' | '1'   | '1'
        'pull keep'       | '0'   | '0'
        'pull overwrite'  | '0'   | '1'
    }

}
