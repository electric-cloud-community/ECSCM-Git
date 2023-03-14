package com.cloudbees.plugin.spec.DataSource

import com.cloudbees.plugin.spec.PluginTestHelper
import com.cloudbees.plugin.spec.WebhookBitbucketSuite

import groovy.json.JsonOutput

class WebhookBitbucketDS {
    // this is map for future possible integration to Test Rail
    //  static def testRailData = [
    //          contentPrefix : "Create new Procedure\n" +
    //                 "Add ${CreateRecord_NextGenS.procedureName} Procedure from ${PluginTestHelper.pluginName} Plugin\n" +
    //                  "With Values\n" +
    //                  "New Procedure Windows Opened\n" +
    //                  "Fill Parameters:\n",uite
    //          contentSuffix : "",
    //          expectedPrefix: "",
    //          expectedSuffix: "",
    //  ]

    //var for help
    
    static def payloadPath = [
        originalName: 'payloadPath',
        correct     : 'webhook_payloads/simple.json'
    ]

    //Not Required parameters
    static def ecRunDuplicates = [
        originalName: 'ec_runDuplicates',
        correct     : '1'
    ]
    
    static def ecQuietTime = [
        originalName: 'ec_quietTime',
        correct     : '0'
    ]
    
    static def ecMaxRetries = [
        originalName: 'ec_maxRetries',
        correct     : '5'
    ]

    //common maps'

    static def expectedOutcome = [
            success: "success",
            error  : "error",
            warning: "warning",
            empty: "",
    ]
}
