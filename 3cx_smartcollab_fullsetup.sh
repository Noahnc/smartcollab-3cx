#!/bin/bash

########################################################################
#         Copyright © by Noah Canadea | All rights reserved
########################################################################
#                           Description
#       Bash Script zum erstellen von btc 3CX smartcollab Instanzen
#
#                    Version 1.0 | 29.12.2020

# Global variables
MyPublicIP=$(curl ipinfo.io/ip)
DependenciesOK=
varDomain=
varContentValid=
varDomainRecordOK=
varLicense=
var3CXPW=
varLicenseContactName=
varLicenseContactCompany=
varLicenseContactEmail=
varLicenseContactPhone=
FormDataOK=
ScriptFolderPath="$(dirname -- "$0")"
ProjectFolderName="smartcollab-3cx"

# Beende das Script sollte ein Fehler auftreten
#set -euo pipefail

# Auffangen des Shell Terminator
trap ctrl_c INT

function CheckPWStrenght() {

  varPasswordOK="false"
  local PW="$1"
  local PWLenght="${#PW}"

  if [[ $PW =~ [0-9] ]] && [[ $PW =~ [a-z] ]] && [[ $PW =~ [A-Z] ]] && [[ $PWLenght -ge 18 ]] && [[ $PW == *['!'@#\$%^\&.,-+*()_+]* ]]; then
    varPasswordOK="true"
  else
    echo -e "\e[31mPasswort entspricht nicht den Komplexitätsanforderungen!\e[39m"
  fi

}

function ctrl_c() {
  echo ""
  echo -e "\e[31mAusführung des Script wurde abgebrochen.\e[39m"

  if [[ $ScriptFolderPath = *"$ProjectFolderName" ]]; then
    rm -r "$ScriptFolderPath"
  fi
  exit 1
}

function OK() {
  echo -e "\e[32m$1\e[39m"
}

function error() {
  echo -e "\e[31m
Fehler beim ausführen des Scripts, folgender Vorgang ist fehlgeschlagen:
$1
Bitte prüfe den Log-Output.\e[39m"
  if [[ $ScriptFolderPath = *"$ProjectFolderName" ]]; then
    rm -r "$ScriptFolderPath"
  fi
  exit 1
}

CreateConfigFile() {

  mkdir -p /etc/btc
  # Erstelle den System Info Text
  cat >/etc/btc/smartcollab_3cx.conf <<EOF
Domain:$1
Company:$2     
EOF

  OK "Konfigfile wurde in /etc/btc/smartcollab_3cx.conf angelegt"
}

function Install3CX() {
  wget -O- http://downloads-global.3cx.com/downloads/3cxpbx/public.key | sudo apt-key add -
  echo "deb http://downloads-global.3cx.com/downloads/debian stretch main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
  sudo apt update
  sudo apt install net-tools dphys-swapfile || error "Installation der 3CX Prequisits"
  sudo apt install 3cxpbx -y || error "Installation der 3CX PBX"

  OK "3CX PBX erfolgreich installiert"
}

function CreateLoginBanner() {

  rm -f /etc/motd
  rm -f /etc/update-motd.d/10-uname

  # Erstelle das Logo
  cat >/etc/update-motd.d/00-logo <<EOF
#!/bin/bash
echo -e " \e[34m
  _____               _               _     _         
 |___ /  _____  __   | |__  _   _    | |__ | |_ ___   
   |_ \ / __\ \/ /   | '_ \| | | |   | '_ \| __/ __|  
  ___) | (__ >  <    | |_) | |_| |   | |_) | || (__ _ 
 |____/ \___/_/\_\   |_.__/ \__, |   |_.__/ \__\___(_)
                            |___/  
__________________________________________________________\e[39m"        
EOF

  # Erstelle den System Info Text
  cat >/etc/update-motd.d/01-infobanner <<EOF
#!/bin/bash
echo -e " \e[34m
Kunde:         $1
3CX Domain:    https://$2
Datum:         \$( date )
OS:            \$( lsb_release -a 2>&1 | grep  'Description' | cut -f2 )
Uptime:        \$( uptime -p )
\e[39m
"        
EOF

  # Neu erstellte Banner ausführbar machen
  chmod a+x /etc/update-motd.d/*

  OK "Login Banner wurde erfolgreich erstellt"
}

function CheckDomainRecord() {

  # Variable zurücksetzen auf default
  varDomainRecordOK="true"

  # Prüfen ob ein A Record gefunden wird, wenn nein wird auf false gesetzt
  host -t a "${1}" | grep "has address" >/dev/null || {
    varDomainRecordOK="false"
    echo -e "\e[31mDie Für ${1} wurde leider kein DNS A Record gefunden\e[39m"
  }

  if [[ $varDomainRecordOK = "true" ]]; then
    varDomainRecordIP=$(host -t a "${1}" | grep "address" | cut -d" " -f4)
    if [[ "$varDomainRecordIP" = "${2}" ]]; then
      varDomainRecordOK="true"
    else
      varDomainRecordOK="false"
      echo -e "\e[31mDie Domain ${1} verweist nicht auf die IP ${2}, sondern auf $varDomainRecordIP\e[39m"
      echo -e "\e[31mPrüfe den DNS Record und die Public IP und versuche es nochmals!\e[39m"
    fi
  fi

}

function RequestCertificate() {

  # Zertifikat beantragen
  certbot certonly --standalone -d "${1}" --non-interactive --agree-tos -m support@btcjost.ch || error "Beantragen des Zertifikats für ${1} über LetsEncrypt fehlgeschlagen"

  # Provisorische kopie ins SSL Directory erstellen für 3CX Setup
  cp /etc/letsencrypt/live/"${1}"/privkey.pem /etc/ssl/ && cp /etc/letsencrypt/live/"${1}"/fullchain.pem /etc/ssl/ || error "Zertifikat für ${1} konnte nicht ins SSL Verzeichniss kopiert werden"

  OK "Zertifikat wurde beantragt und gespeichert"
}

function ConfigureCertbot() {

  # pre und post Hook erstellen (wird jedes mal vor und nach Zertifikatserneuerung ausgeführt)
  echo "pre_hook = service nginx stop" >>"/etc/letsencrypt/renewal/${1}.conf" || error "Cerbot Pre-Hook konnte nicht angelegt werden"
  echo "post_hook = cp /etc/letsencrypt/live/${1}/privkey.pem /var/lib/3cxpbx/Bin/nginx/conf/Instance1/${1}-key.pem && cp /etc/letsencrypt/live/${1}/fullchain.pem /var/lib/3cxpbx/Bin/nginx/conf/Instance1/${1}-crt.pem && service nginx start" >>"/etc/letsencrypt/renewal/$varDomain.conf" || error "Cerbot Post-Hook konnte nicht angelegt werden"

  OK "Post und Pre-Hook wurden erfolgreich angelegt"
}

function SetupFW() {

  # Konfigurieren der Firewall.
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22
  ufw allow 80
  ufw allow 443
  ufw allow 5090
  yes | ufw enable

}

function Create3CXConfig() {

  local varTrunkMainNumber="${varLicenseContactPhone:1}"

  mkdir -p /etc/3cxpbx
  cat >/etc/3cxpbx/setupconfig.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<SetupConfig xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <tcxinit>
    <option>
      <code>InstallationType</code>
      <answer>new</answer><!--New install "new", restore Backup  = "restore"-->
    </option>
    <option>
      <code>LicenseKey</code>
      <answer>$varLicense</answer>
    </option>
    <option>
      <code>BackupFile</code><!--If New install skip this-->
      <answer /><!--If you want to restore a backup put a reachable path from where the backup can be downloaded from. Can be actual physical path on local machine or http link-->
    </option>
    <option>
      <code>BackupPassword</code><!--Password for backup file (if backup is encrypted)-->
      <answer />
    </option>
    <option>
      <code>AdminUsername</code>
      <answer>btcadmin</answer><!--Admin Username-->
    </option>
    <option>
      <code>AdminPassword</code>
      <answer>$var3CXPW</answer><!--Admin Pasword-->
    </option>
    <option>
      <code>PublicIP</code>
      <answer>auto</answer><!--"auto" means automatically detect the ip address. Useful in most cases. Otherwise you can put "manual" and fill in Manual Public IP below-->
    </option>
    <option>
      <code>ManualPublicIP</code><!--If public IP = "manual" enter ip here. if "auto" skip-->
      <answer />
    </option>
    <option>
      <code>StaticOrDynamicIP</code>
      <answer>static</answer><!--If your public ip is Static (does not change) use "static" otherwise use "dynamic"-->
    </option>
    <option>
      <code>LocalIP</code><!--Here we ask to choose the local ip of the machine. If you have no nat then the public is taken--> 
      <answer>auto</answer><!--if auto it takes the first ip on the network stack in the list. If you answer with the "manual" option (in multiple nic adapters you will have more interfaces,) then you need to populate the next option ManualLocalIP with the local IP Address you want"-->
    </option>
    <option>
      <code>ManualLocalIP</code><!--Answer only if above question you choose that you want to enter ip manually-->
	  <answer></answer>
    </option>
    <option>
      <code>NeedFqdn</code>
      <answer>no</answer><!-- enter "yes" to get a 3CX FQDN. enter "no" to use your fqdn (custom domains)-->
    </option>
    <option>
      <code>Hostname</code>
      <answer></answer><!--enter your hostname example contoso - the company name - This option needs to be filled in if NeedFqdn is yes. Skip if need fqdn is NO-->
    </option>
	<option>
	  <code>DomainGroup</code>
	  <answer>Europe</answer>
	</option>
    <option>
      <code>DnsSuffix</code> <!--This option needs to be selected in NeedFqdn is yes. List of available suffixes per Domain Group can be found on:https://activation.3cx.com/apiv2/domains Skip if need fqdn is NO. -->
      <answer>eu</answer>
    </option>
    <option>
      <code>FullExternalFqdn</code><!--This should be populated if NeedFqdn = "no". -->
      <answer>$varDomain</answer><!--User selected needfqdn = no. This means you have an fqdn so enter your fully qualified domain here example pbx.contoso.com-->
    </option>
    <option>
      <code>CertificatePath</code><!--Use if NeedFqdn = "no". -->
      <answer>$varFullChainPath</answer><!--This is the certificate file which can be either a path, http link or just copy and paste the whole contents of the certificate - Including the "BEGIN certificate part"-->
    </option>
    <option>
      <code>CertificatePassword</code><!--Use if NeedFqdn = "no". -->
      <answer>PASSWORD</answer><!--This is the PFX certificate password. Shows only when you select a pfx file"-->
    </option>
    <option>
      <code>CertificateKey</code><!--Use if NeedFqdn = "no". -->
      <answer>$varKeyPath</answer><!--This is the certificate key which can be either a path, http link or it can be the whole contents of the pem file.. Including the "BEGIN certificate part Applies to PEM Certs"--> 
    </option>
    <option>
      <code>CertificateKeyPasswordRequest</code><!--Use if NeedFqdn = "no". -->
      <answer /><!-- It could be that the pem file is encrypted, so without the key, setupconfig will download the file but will not be able to decrypt it unless we enter the password request key here.-->
    </option>
    <option>
      <code>HasLocalDns</code><!--"yes" assumes that you have a manageable local dns example windows dns. "no" assumes that you do not have a dns and therefore will fallback to using IP Addresses --> 
      <answer>yes</answer>
    </option>
    <option>
      <code>InternalFqdn</code><!--Used when HasLocalDns = yes. Can be skipped if HasLocalDns = no-->
      <answer>$varDomain</answer><!--this is the full internal FQDN. If in HasLocalDns  you select "yes", this means you have a managed dns so therefore we need to know the FQDN local. if you select 2 then you can skip this out. "-->
    </option>
    <option>
      <code>HttpsPort</code>
      <answer>443</answer>
    </option>
    <option>
      <code>HttpPort</code>
      <answer>80</answer>
    </option>
	<option>
      <code>SipPort</code>
      <answer>5060</answer>
    </option>
	<option>
      <code>TunnelPort</code>
      <answer>5090</answer>
    </option>
    <option>
      <code>NumberOfExtensions</code> <!--How many digits your extensions should have. Default is 3 Digits. Note that the system reserves 30 numbers for system extension. This can not be changed later. -->
      <answer>3</answer>
    </option>
    <option>
      <code>AdminEmail</code>
      <answer>support@btcjost.ch</answer> <!-- Email for important system notifications such as 3CX Updates, Service failures, Hacking attempts, Network Errors, Emergencies and other diagnostics.-->
    </option>
	<option>
    <code>MailServerType</code>
      <answer>3CX</answer>
    </option>
    <option>
      <code>MailServerAddress</code> <!-- Email server details to be used for notifications, voicemails and invites. You can use a Gmail account. More info here: https://www.3cx.com/blog/docs/gmail-mail-server/-->
      <answer>smtp.mycompany.com</answer>
    </option>
    <option>
      <code>MailServerReplyTo</code>
      <answer>noreply@mycompany.com</answer>
    </option>
    <option>
      <code>MailServerUserName</code> <!-- Can be empty -->
      <answer>user</answer>
    </option>
    <option>
      <code>MailServerPassword</code> <!-- Can be empty -->
      <answer>password</answer>
    </option>
    <option>
      <code>MailServerEnableSslTls</code>
      <answer>yes</answer>
    </option>
	<option>
	  <code>Continent</code> 
	  <answer>Europe</answer>
	</option>
    <option>
      <code>Country</code> <!-- Country name from here http://www.3cx.com/wp-content/uploads/2016/11/Time-Zone-Sheet1-1.pdf  -->
      <answer>Switzerland</answer>
    </option>
    <option>
      <code>Timezone</code> <!--get codes from here http://www.3cx.com/wp-content/uploads/2016/11/Time-Zone-Sheet1-1.pdf -->
      <answer>58</answer>
    </option>
    <option>
      <code>OperatorExtension</code>
      <answer>900</answer>
    </option>
    <option>
      <code>OperatorFirstName</code> <!-- Operator first name. Can be empty. -->
      <answer></answer>
    </option>
    <option>
      <code>OperatorLastName</code> <!-- Operator last name. Can be empty. -->
      <answer></answer>
    </option>
    <option>
      <code>OperatorEmail</code>
      <answer>support@btcjost.ch</answer>
    </option>
    <option>
      <code>OperatorVoicemail</code>
      <answer>999</answer>
    </option>
    <option>
      <code>Promptset</code>
      <answer>German</answer> <!-- get data from http://downloads.3cx.com/downloads/v150/templates/promptsets/promptsets.xml-->
    </option>
    <option>
      <code>LicenseContactName</code>
      <answer>$varLicenseContactName</answer>
    </option>
    <option>
      <code>LicenseCompanyName</code>
      <answer>$varLicenseContactCompany</answer>
    </option>
    <option>
      <code>LicenseEmail</code>
      <answer>$varLicenseContactEmail</answer>
    </option>
    <option>
      <code>LicensePhone</code>
      <answer>$varLicenseContactPhone</answer>
    </option>
    <option>
      <code>ResellerId</code> <!-- Id of reseller. Can be empty-->
      <answer></answer>
    </option>
  </tcxinit>
  <siptrunk>
    <Name>Peoplefone</Name>
    <TemplateFilename>peoplefonech.pv.xml</TemplateFilename> <!-- Template file name from C:\ProgramData\3CX\Instance1\Data\Http\Templates\provider -->
    <Host>sips.peoplefone.ch</Host> <!-- Registrar/Server/Gateway Hostname or IP -->
    <Port>5060</Port>
    <ProxyHost></ProxyHost> <!-- Outbound Proxy of sip trunk -->
    <ProxyPort>5060</ProxyPort> <!--Proxy port-->
    <SimultaneousCalls>100</SimultaneousCalls> <!-- Number of SIM Calls -->
    <RequireRegistrationFor>InOutCalls</RequireRegistrationFor> 
	<!-- Type of Authentication possible values: "Nothing" - No registration required, "IncomingCalls" - Registration is only required for incoming calls, "OutgoingCalls" - Registration is only required for outgoing call, "InOutCalls"	- Registration is required for both incoming and outgoing calls -->
    <AuthID></AuthID> <!-- Authentication ID (aka SIP User ID) -->
    <AuthPassword></AuthPassword> <!-- Authentication Password -->
    <Use3WayAuth>false</Use3WayAuth> <!-- Use 3 Way Authentication can be true or false -->
    <SeparateAuthPassword></SeparateAuthPassword> <!-- Authentication Password for 3 way authentication -->
    <ExternalNumber>$varTrunkMainNumber</ExternalNumber> <!-- Main Trunk Number -->
    <OfficeHoursDestinationType>Extension</OfficeHoursDestinationType> 
	<!-- Destination for calls during office hours, possible values: "None" - end call, "Extension", "VoiceMail", "External" - destination is external number, "Fax" - destination is Fax number -->																		
    <OfficeHoursDestination>900</OfficeHoursDestination>  <!-- Destination for calls during office hours (number) -->
    <OutOfOfficeHoursDestinationType>Extension</OutOfOfficeHoursDestinationType>
	<!-- Destination for calls outside office hours, possible values: "None" - end call, "Extension", "VoiceMail", "" - destination is external number, "Fax" - destination is Fax number -->	
    <OutOfOfficeHoursDestination>900</OutOfOfficeHoursDestination> <!-- Destination for calls during out of office hours (number) -->
    <DIDNumbers></DIDNumbers> <!--enter DID numbers that the provider gave you here in comma separated form.-->
    <OutboundCallerID>$varTrunkMainNumber</OutboundCallerID>
    <Direction>Both</Direction> 
	<!-- Allow inbound/outbound calls, possible value: 
	Both - Both inbound and outbound calls can be made on this line - default option 
	None - No calls can be made on this line, 
	Inbound - Only inbound calls can be made on this line, 
	Outbound - Only outbound calls can be made on this line, -->	

	<!-- PBX Delivers Audio true / false-->
	<DeliverAudio>true</DeliverAudio> 

	<!--Disallow video calls--> 
	<DisableVideoCalls>true</DisableVideoCalls>

	<!--Supports Re-Invite-->
	<SupportReinvite>false</SupportReinvite>

	<!--Supports Replaces-->
	<SupportReplaces>false</SupportReplaces>

	<!--Put Public IP in SIP VIA Header-->
	<PublicIpInSipViaHeader>$MyPublicIP</PublicIpInSipViaHeader> <!-- Optional. Can be empty or absent -->

	<!-- SRTP-->
	<EnableSRTP>false</EnableSRTP> 

    <TimeBetweenReg>60</TimeBetweenReg> <!-- Re-Register Timeout -->
	<!--Select which IP to use in 'Contact' (SIP) and 'Connection'(SDP) fields
	Available options are 
	"Default"
	"Local"
	"Specified"
	-->
	<!--IPcontactsdp 2.2.2.2:5061--> 
    <IPInRegistrationContact>Default</IPInRegistrationContact>
    <SpecifiedIPForRegistrationContact></SpecifiedIPForRegistrationContact>

    <Codecs> <!-- Codec Priority adjust depending on what the sip trunk supports-->
	  <codec>G.711 A-law</codec>
	  <codec>G.711 U-law</codec>
    <codec>G729</codec>
    </Codecs>
  </siptrunk>
  <OutboundRules>
    <OutboundRule>
      <Name>0</Name>
	  <Prefix>0</Prefix>
	  <DNRanges> <!--Calls from extensions example 000,100-105-->
        <DNRange>
          <To></To>
          <From></From>
        </DNRange>
        <DNRange>
          <To></To>
          <From></From>
        </DNRange>
      </DNRanges>
	  <NumberLengthRanges></NumberLengthRanges> <!-- can be comma-separated string of lengths as well: 9,10,11 -->
      <DNGroups> <!--add the group or groups here-->
        <Group></Group>
        <Group></Group>
      </DNGroups>
      <OutboundRoutes>
        <OutboundRoute>
          <Gateway>Peoplefone</Gateway>
		      <StripDigits>0</StripDigits>
		      <Prepend></Prepend>
        </OutboundRoute>
      </OutboundRoutes>
    </OutboundRule>
    <OutboundRule>
      <Name>00</Name>
	  <Prefix>00</Prefix>
	  <DNRanges> <!--Calls from extensions example 000,100-105-->
        <DNRange>
          <To></To>
          <From></From>
        </DNRange>
        <DNRange>
          <To></To>
          <From></From>
        </DNRange>
      </DNRanges>
	  <NumberLengthRanges></NumberLengthRanges> <!-- can be comma-separated string of lengths as well: 9,10,11 -->
      <DNGroups> <!--add the group or groups here-->
        <Group></Group>
        <Group></Group>
      </DNGroups>
      <OutboundRoutes>
        <OutboundRoute>
          <Gateway>Peoplefone</Gateway>
		      <StripDigits>1</StripDigits>
		      <Prepend></Prepend>
        </OutboundRoute>
      </OutboundRoutes>
    </OutboundRule>
  </OutboundRules> 
</SetupConfig>
EOF

  OK "3CX Konfig erfolgreich erstellt"

}

########################################## Script entry point ################################################

echo -e " \e[34m
                  _____               _               _     _         
                 |___ /  _____  __   | |__  _   _    | |__ | |_ ___   
                   |_ \ / __\ \/ /   | '_ \| | | |   | '_ \| __/ __|  
                  ___) | (__ >  <    | |_) | |_| |   | |_) | || (__ _ 
                 |____/ \___/_/\_\   |_.__/ \__, |   |_.__/ \__\___(_)
                                            |___/  
____________________________________________________________________________________________

Dies ist das Setup Script für btc 3CX Smartcollab Systeme.

Bitte stelle sicher, das folgende Bedingungen erfüllt sind, bevor du mit der Installation fortfährtst:
- Auf dem Edge Gateway wurden die Ports 80 und 443 auf die IP $MyPublicIP geöffnet.
- Es wurde ein smartcollab.ch DNS Record für den Kunden auf die IP $MyPublicIP angelegt.
- Du hast einen 3CX Lizenzschlüssel bereit.
\e[39m
"

# Auslesen ob alle Bedingungen erfüllt sind
while [[ $DependenciesOK != @("j"|"n") ]]; do
  read -r -p "Sind alle Bedingungen erfüllt? (j = Ja, n = Nein): " DependenciesOK
done

# Script beenden, wenn nicht alle Bedingungen OK
if [[ $DependenciesOK == "n" ]]; then
  echo "Bitte sorg dafür dass alle Bedingunen erfüllt sind und starte dann das Script erneut, bis bald."
  rm -r "$ScriptFolderPath"
  exit
fi

while [[ $FormDataOK != "j" ]]; do

  varContentValid="false"
  while [[ $varContentValid = "false" ]]; do
    echo "Folgende public IP wurde erkannt, drücke Enter wenn diese korrekt ist oder passe sie manuell an:"
    read -r -e -p "IP: " -i "$MyPublicIP" MyPublicIP
    if ! [[ $MyPublicIP =~ [^0-9.] ]]; then
      varContentValid="true"
    else
      echo -e "\e[31mKeine gültige Eingabe!\e[39m"
    fi
  done

  varDomainRecordOK="false"
  while [[ $varDomainRecordOK = "false" ]]; do
    echo "Bitte die gewünschte smartcollab.ch Subdomain eingeben:"
    read -r -e -p "Domain: " -i "$varDomain" varDomain
    CheckDomainRecord "$varDomain.smartcollab.ch" "$MyPublicIP"
  done

  varContentValid="false"
  while [[ $varContentValid = "false" ]]; do
    echo "Bitte den 3CX Lizenzschlüssel eingeben:"
    read -r -e -p "Lizenz: " -i "$varLicense" varLicense
    if ! [[ $varLicense =~ [^0-9a-zA-Z-] ]]; then
      varContentValid="true"
    else
      echo -e "\e[31mKeine gültige Eingabe!\e[39m"
    fi
  done

  varPasswordOK="false"
  while [[ $varPasswordOK = "false" ]]; do
    echo "Bitte ein 3CX MGM PW eingeben (mindestens 18 Zeichen, 1 Grossbuchstabe, 1 Kleinbuchstabe, 1 Zahl und 1 Sonderzeichen):"
    read -r -e -p "Passwort: " -i "$var3CXPW" var3CXPW
    CheckPWStrenght "$var3CXPW"
  done

  varContentValid="false"
  while [[ $varContentValid = "false" ]]; do
    echo "Bitte den vollen Namen der Kontaktperson des Kunden eingeben (wird für Lizenzregistrierung verwendet):"
    read -r -e -p "Name: " -i "$varLicenseContactName" varLicenseContactName
    if ! [[ $varLicenseContactName =~ [^a-zA-Z" "] ]]; then
      varContentValid="true"
    else
      echo -e "\e[31mKeine gültige Eingabe!\e[39m"
    fi

  done

  varContentValid="false"
  while [[ $varContentValid = "false" ]]; do
    echo "Bitte den Firmennamen des Kunden eingeben (wird für Lizenzregistrierung verwendet):"
    read -r -e -p "Firma: " -i "$varLicenseContactCompany" varLicenseContactCompany
    if ! [[ $varLicenseContactCompany =~ [^a-zA-Z0-9" "] ]]; then
      varContentValid="true"
    else
      echo -e "\e[31mKeine gültige Eingabe!\e[39m"
    fi

  done

  varContentValid="false"
  while [[ $varContentValid = "false" ]]; do
    echo "Bitte die E-Mail der Kontaktperson des Kunden eingeben (wird für Lizenzregistrierung verwendet):"
    read -r -e -p "E-Mail: " -i "$varLicenseContactEmail" varLicenseContactEmail
    if ! [[ $varLicenseContactEmail =~ [^a-zA-Z0-9@.] ]]; then
      varContentValid="true"
    else
      echo -e "\e[31mKeine gültige Eingabe!\e[39m"
    fi
  done

  varContentValid="false"
  while [[ $varContentValid = "false" ]]; do
    echo "Bitte die HRN der Firma eingeben in folgendem Format +41444444444:"
    read -r -e -p "HRN: " -i "$varLicenseContactPhone" varLicenseContactPhone
    if [[ ${#varLicenseContactPhone} = 12 ]] && ! [[ $varLicenseContactPhone =~ [^0-9+] ]]; then
      varContentValid="true"
    else
      echo -e "\e[31mKeine gültige Rufnummer!\e[39m"
    fi
  done

  echo "
Bitte Kontrolliere ob die angaben so korrekt sind (nachträgliches ändern ist nicht möglich!):
#############################################################################################

  Domain: $varDomain.smartcollab.ch
  Public IP: $MyPublicIP
  3CX Lizenz: $varLicense
  Admin PW 3CX: $var3CXPW
  Kontaktperson Kunde: $varLicenseContactName
  Firmenname: $varLicenseContactCompany
  Kontaktperson E-Mail: $varLicenseContactEmail
  Kontaktperson Telefon: $varLicenseContactPhone
  "
  read -r -p "Sind alle Angaben korrekt? (j = Ja, n = Nein): " FormDataOK

done

apt-get updates && apt-get upgrade -y

apt-get install host -y

varDomain="$varDomain.managed-network.ch"

# UFW Firewall installieren
if ! [ -x "$(command -v ufw)" ]; then
  apt-get install ufw -y || error "Installation der UFW Firewall fehlgeschlagen"
  OK "UFW Firewall wurde erfolgreich einstalliert"
else
  OK "UFW ist bereits installiert"
fi

# Certbot installieren
if ! [ -x "$(command -v certbot)" ]; then
  apt-get install certbot -y || error "Installation von Certbot fehlgeschlagen"
  OK "Certbot erfolgreich installiert"
else
  OK "Certbot ist bereits installiert"
fi

if ! [ -d "/etc/letsencrypt/live/$varDomain/" ]; then

  # Standalone Zertifikat requesten
  RequestCertificate "$varDomain"

  # Pre und Post Hook für Certbot erstellen
  ConfigureCertbot "$varDomain"

else
  OK "Zertifikat wurde bereits angelegt"
fi

varFullChainPath="/etc/ssl/fullchain.pem"
varKeyPath="/etc/ssl/privkey.pem"

# Firewall konfigurieren
#CreateFWConfig

# Setzen der Zeitzone
timedatectl set-timezone Europe/Zurich

# Erstellen der 3CX XML autosetup config
Create3CXConfig

Install3CX

CreateConfigFile "$varDomain" "$varLicenseContactCompany"

# Löschen des Temporären Zertifikats und Key
if [[ -f "$varFullChainPath" ]]; then
  rm $varFullChainPath
  OK "Temp. Zertifikat wurde entfern"
fi
if [[ -f "$varKeyPath" ]]; then
  rm $varKeyPath
  OK "Temp. Schlüssel wurde entfern"
fi

# Generieren des Login Banner
CreateLoginBanner "$varLicenseContactCompany" "$varDomain"

echo -e " \e[34m
                  _____               _               _     _         
                 |___ /  _____  __   | |__  _   _    | |__ | |_ ___   
                   |_ \ / __\ \/ /   | '_ \| | | |   | '_ \| __/ __|  
                  ___) | (__ >  <    | |_) | |_| |   | |_) | || (__ _ 
                 |____/ \___/_/\_\   |_.__/ \__, |   |_.__/ \__\___(_)
                                            |___/  
____________________________________________________________________________________________

Dein 3CX System der Firma $varLicenseContactCompany wurde erfolgreich Erstellt!

So kannst du dich beim Management-Portal anmelden:
URL: https://$varDomain
Benutzername: btcadmin
Passwort: $var3CXPW
\e[39m
"

########################################## Script end ################################################

# Löschen des Script wenn fertig
if [[ $ScriptFolderPath = *"$ProjectFolderName" ]]; then
  rm -r "$ScriptFolderPath"
fi
