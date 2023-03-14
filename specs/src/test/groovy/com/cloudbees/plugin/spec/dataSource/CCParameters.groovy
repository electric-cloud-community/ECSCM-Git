package com.cloudbees.plugin.spec.dataSource

import com.cloudbees.plugin.spec.PluginTestHelper

class CCParameters {

    //common variables

    static def testRailData = [
            contentPrefix : "Create new Procedure\n" +
                    "Add  Checkout Code Procedure from ECSCM-Git Plugin\n" +
                    "With Values\n" +
                    "New Procedure Windows Opened\n" +
                    "Fill Parameters:\n",
            contentSuffix : "",
            expectedPrefix: "",
            expectedSuffix: "",
    ]
    static def resultPropertyBase = '/myJob/'

    static def checkBox = [
            unchecked: 0,
            checked  : 1,
    ]

    // Required Params for Procedure
    static def configurationName = [
            sanity   : "configGitSanity",
            positive : "configGitPositive",
            negative : "configGitNegative",
            incorrect: "incorrectConfigName",
            empty    : "",
    ]

    //Not Required Parameters

    static def clone = checkBox

    static def overwrite = checkBox

    static def commit = [
            correct1  : "141d71a1c460afa71fe4f6bed2b4a0c9046aeb82",
            correct2  : "9fa72be91009bd8e726cdd59394faee429f47296",
            incorrect: "112233",
            empty    : "",
    ]

    static def depth = [
            correct  : "2",
            incorrect: "-1",
            empty    : "",
    ]

    static def dest = [
            correct  : "/tmp/GitTestFolder",
            incorrect: "incorrectFolder",
            empty    : "",
    ]

    static def gitBranch = [
            correct1 : "ForGitTesting1_do_not_touch",
            correct2 : "ForGitTesting2_do_not_touch",
            incorrect: "incorrectBranch",
            empty    : "",
    ]

    static def gitRepo = [
            correct  : "https://github.com/electric-cloud/FlowPluginsTestGen.git",
            incorrect: "https://github.com/electric-cloud/IncorrectRepository.git",
            empty    : "",
    ]

    static def tag = [
            correct  : "",
            incorrect: "",
            empty    : "",
    ]


    static def expectedSummary = [
            empty:"",
    ]
}