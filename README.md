## 1. 파이썬 환경변수 docker-compose 업데이트 

#### 📂 디렉토리 및 파일 구조

- 아래와 같은 구조로 프로젝트 디렉토리와 파일 구성.

```bash
.
├── docke  r-compose.base.yml   # 모든 환경에서 공통으로 사용할 템플릿
├── update_compose.py         # Python 스크립트
├── run_update.sh             # Bash 실행 스크립트
├── dev/
│   └── app.dev.env               # 개발 환경 변수 파일
├── qa/
│   └── app.qa.env                # QA 환경 변수 파일
└── prd/
    └── app.prd.env               # 운영 환경 변수 파일

```

## 2. Jenkins 공통함수

```bash
// =============================================================================
//  검증/운영 원격 배포 서버 정보 (Remote Build Server Info) 
// =============================================================================
def QA_SERVERS = [
    [
        name: 'dptmxpmpappqw01',
        host: '10.173.193.68',                       // 운영 VM1 IP/호스트명
        user: '',                                    // 운영 VM1 접속 계정
        identityFile: '',
 //       credentialsId: 'nib-prod-vm1-ssh-credential',    // (SSH Username with private key 권장)
        allowAnyHosts: true
    ],
    [
        name: 'dptmxpmpappqw02',
        host: '10.173.193.59',                       // 운영 VM2 IP/호스트명
        user: '',                      // 운영 VM2 접속 계정
        identityFile: '',
//        credentialsId: 'nib-prod-vm2-ssh-credential',    // (SSH Username with private key 권장)
        allowAnyHosts: true
    ]
]


def Map<String, Object> initConfigEnv = [:]  //환경변수

// =============================================================================
//  공통함수
// 1.단일 따옴표 안전 이스케이프 : ' -> '"'"'
// =============================================================================
def toShEscape(String v) {
    if (v == null) return "''"
    def vEx =  "'" + v.replace("'", "'\"'\"'") + "'"
    // echo "jenkins toShEscape: ${vEx}"
    return vEx
}

// =============================================================================
//  공통함수
// 2.env 맵을  export 구문(AND 체인)으로 변환
// =============================================================================
def toExportChain(Map<String, Object> envMap) {
    return envMap.collect { k,v -> "export ${k}=" +
                 toShEscape(v?.toString() ?: "")}.join(' && ')
}

// =============================================================================
// 공통함수
// 3.오른쪽 공백 제거
// =============================================================================
def rtrim(String rt) {
    if (rt == null) return ''
    //줄 끝의 공백/탭 등만 제거
    return rt.replaceAll(/\s+$/,'')
}

// =============================================================================
// 공통함수
// 3.멀티라인 명령 -> 빈줄/주석 제거하고 원래 줄 구조 유지
// =============================================================================
def toFilteredLiner(String cmd) {
    return cmd.readLines()
            .collect { line -> rtrim(line) }   //끝 공백만 제거
            .findAll { line ->
                def t = line.trim()
                    return t && !t.startsWith('#')     //빈줄/주석 제외
            }
            .join('\n')     //줄바꿈
}


// =============================================================================
//  공통함수
// 4.sshRunAlwaysHeredoc(host,user,credId,rawCmd, extraEnv = [:], sudoE = false)
// rawCmd : 멀티라인 (자동  && 체인)
// extraEnv : export 앞에 주입
// sudoE : true 면 'sudo -E bash -lc' 로 실행
// returnE : true 면 결과값을 리턴
// =============================================================================
def sshRunAlwaysHeredoc(String rawCmd,Map<String,Object> extraEnv = [:], boolean sudoE = false, boolean returnE = false) {
    // echo "jenkins env: ${sshconfig}"
    //기본 env + 추가 envi
    // 공통 환경변수 선언
    //APP_PATH : env.APP_PATH,
    //TAG : env.TAG
    Map<String,Object> mergedEnv = [
        OS_USER : "${env.OS_USER}",
        OS_OWNER : "${env.OS_OWNER}",
        BUILD_APP_TAG : "${env.BUILD_APP_TAG}",
        BUILD_MODE : "${env.BUILD_MODE}"
        ] + extraEnv

    String exportChain = toExportChain(mergedEnv)
    String bashPrefix = sudoE ? 'sudo -E bash -lc' : 'bash -lc'
    def filterRawCmd = toFilteredLiner(rawCmd)
    String scriptBody

   if  (returnE) {
    // 제어문 : heredoc으로 안전하게 전달 (원격에서 변수 확장)
    scriptBody = """
        ${bashPrefix} ${toShEscape("""\
        set -eo pipefail
        TMPDIR=\$(mktemp -d /tmp/jenkins_cmd_XXXXXXXXXXXX)
        trap 'rc=\$?; rm -rf "\$TMPDIR"; exit \$rc' EXIT INT TERM
cat <<'EOS' > "\$TMPDIR/tmprun.sh"
#!/bin/bash
set -eo pipefail
${exportChain}
\n
${filterRawCmd}
exit 0
EOS
        chmod 777 "\$TMPDIR"
        chmod +x "\$TMPDIR/tmprun.sh"
        ##"\$TMPDIR/tmprun.sh"
        ## 스크립트 실행(stderr는 콘솔 stdoutd은 변수로)
        OUT=\$(echo '$PRD_MX_ADM_PW' | su - $OS_USER -c "bash \$TMPDIR/tmprun.sh" 2> >(cat 1>&2) || true)
        ## __RESULT__: 로 시작하는 마지막 줄만 추출
        LINE=\$(printf "%s" "\$OUT" | awk '/^__RESULT__:/ {keep=\$0} END{if(keep) print keep}')
        ##접두사 제거 및 트리밍
        LAST_LINE=\$(printf "%s" "\$LINE" | sed -E 's/^__RESULT__:\\s*//; s/^\\s+//; s/\\s+\$//')
        printf "%s\\n" "\$LAST_LINE"
        """.stripIndent())}
    """.trim()

    } else {

     // 제어문 : heredoc으로 안전하게 전달 (원격에서 변수 확장)
    scriptBody = """
        ${bashPrefix} ${toShEscape("""\
        set -eo pipefail
        TMPDIR=\$(mktemp -d /tmp/jenkins_cmd_XXXXXXXXXXXX)
        trap 'rc=\$?; rm -rf "\$TMPDIR"; exit \$rc' EXIT INT TERM
cat <<'EOS' > "\$TMPDIR/tmprun.sh"
#!/bin/bash
set -eo pipefail
${exportChain}
\n
${filterRawCmd}
exit 0
EOS
        chmod 777 "\$TMPDIR"
        chmod +x "\$TMPDIR/tmprun.sh"
        echo '$PRD_MX_ADM_PW' | su - $OS_USER -c "bash \$TMPDIR/tmprun.sh"

        """.stripIndent())}
    """.trim()
}
    return scriptBody
}


// =============================================================================
//  원격 실행 함수 (Remote Execution Function)
// =============================================================================
/**
 * 원격 서버에서 셸 커맨드를 실행.
 * @param config Map: 실행 설정값
 * - remote: sshCommand에 전달할 원격 서버 정보 (name, host, user, credentialsId 등)
 * - command: 원격 서버에서 실행할 셸 스크립트 문자열
 */
def remoteExecute(Map config) {
    // sshCommand 스텝을 사용하여 원격지에서 스크립트 실행
     sshCommand remote: config.remote, command: config.command
}

// =============================================================================
//  원격 실행 함수 (Remote Execution Function)
// =============================================================================
/**
 * 원격 서버에서 셸 커맨드를 실행하고 그 결과를 반환합니다.
 * 사용자스크립트에 아래 추가
 *  리턴 값을 사용하는 경우 아래와 같이 __RESULT__ 에 값을 대입하여 보냄
 *  printf "__RESULT__:%s\\n" "\$LATEST_TAG"
 * @param config Map: 실행 설정값
 * - remote: sshCommand에 전달할 원격 서버 정보 (name, host, user, credentialsId 등)
 * - command: 원격 서버에서 실행할 셸 스크립트 문자열 *
 * @return String: 원격 명령어의 표준 출력(stdout) 결과
 */
def remoteExecuteAndGetOutput(Map config) {

    def raw = sshCommand (remote: config.remote, command: config.command)
    def resultOut = raw?.trim()
    //실행 결과를 반환받음
    return resultOut?.length() ? resultOut : null
}


```

## 3. SSH credentials 값 처리 방법 

```script

// 젠킨스 credentials 추출 .env 설정
stage('Deploy and Verify QA Server 1') {
    steps {
        script {
                //# Jenkins 변수를 셸 변수로 설정
                initConfigEnv = [:]

                def QAServer = QA_SERVERS[0]
                envStrWithCredentials(QAServer,initConfigEnv) 
                
        }
    }
}

/**
 *  credential 바인딩 + deployToServer 호출을 한 번에 처리.
 * 서버별 스테이지가 각자 withCredentials 블록을 반복 작성하지 않도록 통합.
 * Jenkins Credentials에 등록된 값을 가져오는경우 여기에 명시하여 사용
 * PRDServer : 서버정보
 * configEnv : 환경변수 
 */
def envStrWithCredentials(QAServer,configEnv) {
                    withCredentials([
                        sshUserPrivateKey(credentialsId: SSH_CREDENTIAL_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER') ,
                        usernamePassword(credentialsId: 'qa-mem-mx-iris-db-credentials',usernameVariable: 'DB_USER', passwordVariable: 'DB_PASS'),
                        usernamePassword(credentialsId: 'qa-mem-mx-be-iris-db-credentials',usernameVariable: 'DB_BE_USER', passwordVariable: 'DB_BE_PASS'),
                        usernamePassword(credentialsId: 'qa-mx-iris-nplm-db-credentials',usernameVariable: 'NPLM_USER', passwordVariable: 'NPLM_PW') ,
                        usernamePassword(credentialsId: 'qa-mem-mx-be-iris-axmonitor-db-credentials',usernameVariable: 'AXMON_BE_USER', passwordVariable: 'AXMON_BE_PASS'),
                        string(credentialsId: 'qa-mem-mx-iris-mendix-lic-credentials', variable: 'LIC_KEY') ,
                        string(credentialsId: 'qa-mx-iris-adm-app', variable: 'ADMIN_PASS'),
                        string(credentialsId: 'qa-mx-iris-iam-api-user-pw', variable: 'IAMAPIUSER_PW'),
                        string(credentialsId: 'qa-mx-iris-saml20-keystore-pw', variable: 'SAML20_KEYSTORE_PASSWORD'),
                        string(credentialsId: 'qa-mx-iris-nplm-consumer-api-key', variable: 'NPLM_DEFAULT_CONSUMER_API_KEY'),
                        string(credentialsId: 'qa-mx-iris-nplm-consumer-pw', variable: 'NPLM_DEFAULT_CONSUMER_PWD') ,
                        string(credentialsId: 'qa-mx-iris-node-pw', variable: 'QA_MX_ADM_PW')
                    ]) {
                    script {
                      
                        echo "--- Running Deploy and Verify ---"

                        def remoteEnvScript = ""

                        // ※ AxMonitor 전용 DB 계정을 쓰려면 위 withCredentials 에
                        //    usernamePassword(credentialsId: 'qa-mx-iris-axmonitor-db-credentials',
                        //                     usernameVariable: 'AXMON_USER', passwordVariable: 'AXMON_PW')
                        //    를 추가하고, 아래 envContent 에도 두 줄을 넣어야 함 (QA Server 2 쪽도 동일)
                               
                        def envContent = """
DB_USER='${DB_USER}'
DB_PASS='${DB_PASS}'
DB_BE_USER='${DB_BE_USER}'
DB_BE_PASS='${DB_BE_PASS}'
AXMON_BE_USER='${AXMON_BE_USER}'
AXMON_BE_PASS='${AXMON_BE_PASS}'
NPLM_USER='${NPLM_USER}'
NPLM_PW='${NPLM_PW}'
LICENSE_KEY='${LIC_KEY}'
ADMIN_PASS='${ADMIN_PASS}'
IAMAPIUSER_PW='${IAMAPIUSER_PW}'
SAML20_KEYSTORE_PASSWORD='${SAML20_KEYSTORE_PASSWORD}'
NPLM_DEFAULT_CONSUMER_API_KEY='${NPLM_DEFAULT_CONSUMER_API_KEY}'
NPLM_DEFAULT_CONSUMER_PWD='${NPLM_DEFAULT_CONSUMER_PWD}'
                        """
 
                        //ssh mapping
                        QAServer.user = "${SSH_USER}"
                        QAServer.identityFile = "${SSH_KEY}"
                        // try-catch 블록으로 원격 실행 실패 시 롤백 로직을 처리
                        try {
 
                            remoteEnvScript = envStrScript(QAServer,envContent)
                            // remoteExecute 함수를 호출하여 원격 서버에서 스크립트 실행
                            remoteExecute(remote: QAServer, command: sshRunAlwaysHeredoc(remoteEnvScript,configEnv,false,false))

                            initConfigEnv = [:]  //환경변수

                        } catch (e) {
                            // 원본 에러를 다시 발생시켜 빌드를 최종적으로 실패 처리
                            throw e
                        }
                    }    
          }     
 
}  

// =============================================================================
//  공통함수
//  Jenkins에서 전달된 환경 변수 설정
//  사전에 환경변수로 선언되어 docker compose 실행시 env 값을 읽어와 처리해야할 경우 선언함.
//  일반환경변수 처리시 사용
//  원자적쓰기 (base64 경유)
//  byte[] bytes = envContent.getBytes('UTF-8')
//  String bs64 = bytes.encodeBase64().toString()
//  writeFile file: 'env.tmp', text: envContent
// =============================================================================
def envStrScript(server,envContent) {


def envStrScript = """
                            #!/bin/bash
                            # -e: 오류 발생 시 즉시 중단
                            # -u: 정의되지 않은 변수 사용 시 오류
                            # -x: 실행되는 모든 명령어를 출력
                            # -o pipefail: 파이프라인의 어느 한 곳이라도 실패하면 전체 실패 처리

                            cd ${env.APP_COMPOSE_PATH}
                            echo "--- Starting env on Remote Server ---"

                            umask 077
cat > .env.tmp <<'EOT'
${envContent}
APM_PRODUCT_GROUP_ID='${env.APM_PRODUCT_GROUP_ID}'
APM_PRODUCT_ID='${env.APM_PRODUCT_ID}'
APM_PRODUCT_PHASE='${env.APM_PRODUCT_PHASE}'
APM_AGENT_PATH='${env.APM_AGENT_PATH}'
APM_APPLICATION_PACKAGES='${env.APM_APPLICATION_PACKAGES}' 
E_NODE_HOSTNAME='${server.name}'
E_APP_NODE_IP='${server.host}' 
E_APP_DATABASE_SID='${env.APP_DATABASE_SID}'
## 임시 데이터처리용
E_APP_BE_DATABASE_JDBC_URL='${env.APP_BE_DATABASE_JDBC_URL}'
E_APP_DATABASE_JDBC_URL='${env.APP_DATABASE_JDBC_URL}'
E_APP_DATABASE_TYPE='${env.APP_DATABASE_TYPE}'
E_NPLM_NPLM_URL='${env.NPLM_NPLM_URL}'
E_NPLM_PLAN_URL='${env.NPLM_PLAN_URL}'
E_NPLM_JDBC_URL='${env.NPLM_JDBC_URL}'
E_ES_HOST='${env.ES_HOST}'
E_MXRUNTIME_APPLICATION_ROOT_URL='${env.MXRUNTIME_APPLICATION_ROOT_URL}'
E_AXMONITOR_BE_DATABASE_JDBC_URL='${env.AXMONITOR_BE_DATABASE_JDBC_URL}'
EOT

                            sudo mv -f .env.tmp  .env
                            sudo chmod 600 .env

                            echo "--- Remote env Finished Successfully ---"
                        """

    return envStrScript
}


```


## 특정 스케줄링 

```bash

SCHEDULED_EVENTS=true
MXRUNTIME_ScheduledEventExecution='SPECIFIED'
MXRUNTIME_MyScheduledEvents="SAML20.SE_LogCleanUp,SAML20.SE_SynchronizeIdPMetadata"

```

#### 1. 스케줄러를 켜는 설정 
Mendix Docker Buildpack은 SCHEDULED_EVENTS 변수를 읽어서 컨테이너에서 스케줄러를 켤지 여부를 판단
기본적으로는 false 설정되어 스케줄러 비활성화, true 면 스케줄러를 활성화

Mendix Runtime 내부설정(Custom Runtime Settings)을 환경변수로 주입해야함
특정 이벤트만을 실행하는경우 ScheduledEventExecution 값을 SPECIFIED 변경 MyScheduledEvents 에 실행할 이벤트 목록 기입

#### 2. MXRUNTIME_ScheduledEventExecution
- 스케줄러가 어떤 이벤트를 실행할지 결정하는 정책
- VALUE : ALL :  모든이벤트 실행 (기본값)
          NONE : 아무실행도 실행하지 않음 
          SPECIFIED : MyScheduledEvents 에 정의된 목록만 실행

#### 3. MXRUNTIME_MyScheduledEvents
- SPECIFIED 모드일때 실행할 화이트 리스트 
- 여러개의 스케줄이벤트 실행시 콤마(,)로 구분 
- 주의 : 대소문자를 정확히 지켜야하고, 공백이 들어가지 않아야함.

