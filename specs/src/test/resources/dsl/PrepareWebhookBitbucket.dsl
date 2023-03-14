package dsl
def accountName = args.accountName
def pipelineName = args.pipelineName
def projectName = args.projectName

// Create the service account
serviceAccount(accountName)
// Create session for the service account
def session = createSession(sessionType: 'webhook', serviceAccountName: accountName)

def properties = [
    '/server/ec_endpoints',
    '/plugins/ECSCM-Git/project/ec_endpoints/githubWebhook/POST',
    '/plugins/ECSCM-Git/project/ec_endpoints/githubWebhook/POST/configurationMetadata',
    '/plugins/ECSCM/project/scm_cfgs',
]

// Set ACL

properties.each { property ->
    aclEntry readPrivilege: 'allow',
        path: property,
        principalName: accountName,
        objectType: 'propertySheet',
        principalType: 'serviceAccount'
}

aclEntry readPrivilege: 'allow',
    projectName: '/plugins/ECSCM/project',
    principalName: accountName,
    objectType: 'project',
    principalType: 'serviceAccount'
    
aclEntry modifyPrivilege: 'allow',
    projectName: '/plugins/ECSCM/project',
    principalName: accountName,
    objectType: 'project',
    principalType: 'serviceAccount'

aclEntry executePrivilege: 'allow',
    projectName: '/plugins/ECSCM/project',
    principalName: accountName,
    objectType: 'procedure',
    principalType: 'serviceAccount',
    procedureName: 'ProcessWebHookSchedules'


aclEntry readPrivilege: 'allow',
    systemObjectName: 'server',
    principalName: accountName,
    objectType: 'systemObject',
    principalType: 'serviceAccount',
    procedureName: 'ProcessWebHookSchedules'


def ecscmProjectName = getPlugin(pluginName: 'ECSCM')?.project?.projectName


aclEntry modifyPrivilege: 'allow',
    readPrivilege: 'allow',
    objectType: 'propertySheet',
    path: '/server/ec_counters',
    principalName: 'project: ' + ecscmProjectName,
    principalType: 'user'

aclEntry modifyPrivilege: 'allow',
    readPrivilege: 'allow',
    objectType: 'propertySheet',
    path: '/server/ec_counters',
    principalName: accountName,
    principalType: 'serviceAccount'

//Grant permissions to the plugin project
def objTypes = ['resources', 'workspaces'];

objTypes.each { type ->
    aclEntry principalType: 'user',
        principalName: "project: " + ecscmProjectName,
        systemObjectName: type,
        objectType: 'systemObject',
        readPrivilege: 'allow',
        modifyPrivilege: 'allow',
        executePrivilege: 'allow',
        changePermissionsPrivilege: 'allow'
}

// Grant permissions to the pipeline
 aclEntry executePrivilege: 'allow',
     projectName: projectName,
     principalName: accountName,
     objectType: 'pipeline',
     principalType: 'serviceAccount',
     pipelineName: pipelineName

return session
