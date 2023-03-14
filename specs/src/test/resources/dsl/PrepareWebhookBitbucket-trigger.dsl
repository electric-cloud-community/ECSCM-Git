deleteSchedule projectName: args.projectName,
               scheduleName: args.scheduleName

project args.projectName, {

    schedule args.scheduleName, {

        pipelineName = args.pipelineName

        property 'ec_customEditorData', {
            // For webhook triggerFlag value is 3
            property 'TriggerFlag', value: '3'
            TriggerPropertyName = '/projects/' + args.projectName + '/' + triggerName
            formType = '$[/plugins/ECSCM-Git/project/scm_form/sentry]'
            scmConfig = args.scmConfig
            args.searchParams.each { k, v ->
                property k.toString(), value: v.toString()
            }

        }

        property 'ec_triggerType', value: 'webhook'
        property 'ec_triggerPluginName', value: 'ECSCM-Git'
    }
}
