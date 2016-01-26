<#
.SYNOPSIS
  Sends a note, link or address via PushBullet to any of your active Devices or Contacts.

.DESCRIPTION
  Sends a note, link or address via PushBullet to any of your active Devices or Contacts.

.PARAMETER PushType
    Required parameter PushType. At this time we support note, link and address.

.PARAMETER Contact
    Required parameter Contact. Can be a registered device name, contact name, or email address.
    Will partial match. If you enter "Foo" and there are Foo1, Foo2 or whatever we do not account for that currently.

.PARAMETER Title
    Required paramter Title. Just a [System.String]

.PARAMETER Message
    Optional paramter Message. This is where what you want to say goes. Again, just a [System.String]

.PARAMETER Link
    Required parameter Link if PushType is 'link'. If you are sending a link it makes no sense to not include one.

.PARAMETER PlaceName
    Required parameter PlaceName if sending and 'address' Push. Again, makes no sense not to tell somebody the name of the palce you are sending them. [System.String]

.PARAMETER PlaceAddress
    Required parameter PlaceAddress if sending a PushType 'address'. Currently handled as a [System.String] but may change to URI parsing and conditional handling since we can send map queries this way.

.INPUTS
  Parameter data as needed.

.OUTPUTS
  PushBullet messages?

.NOTES
  Version:        1.0
  Author:         Erick Kinnee
  Creation Date:  01/18/205
  Purpose/Change: Initial script development
  
.EXAMPLE
  .\Push-Bullet.ps1 -PushType note -Contact 'chrome' -Title 'Test' -Message 'Woop'
#>
[CmdletBinding()]
param
(
    #Different types of pushes
    #Note: type = 'note', title = title, body = message 
    #Link: type = 'link', title = title, body = message, url = url
    #Address: type = 'address', name = placename, address = placeaddress or mapsearchquery
    #Checklist: type = 'list', title = title, items  = list of strings ["one", "two", "three"].
    #File: type = 'file', filename = filename, filetype = "MIME type", fileurl = url, body = message
        
    [Parameter(ParameterSetName='note', Mandatory=$False)]
    [Parameter(ParameterSetName='link',Mandatory=$False)]
    [Parameter(ParameterSetName='address',Mandatory=$False)]
    [ValidateSet('note', 'link', 'address')]
    [System.String] $PushType = 'note',
    [Parameter(ParameterSetName='note', Mandatory=$True)]
    [Parameter(ParameterSetName='link',Mandatory=$True)]
    [System.String] $Title,
    [Parameter(ParameterSetName='note', Mandatory=$True)]
    [Parameter(ParameterSetName='link',Mandatory=$False)]
    [System.String] $Message,
    [Parameter(ParameterSetName='link',Mandatory=$True)]
    [System.String] $Link,
    [Parameter(ParameterSetName='address',Mandatory=$True)]
    [System.String] $PlaceName,
    [Parameter(ParameterSetName='address',Mandatory=$True)]
    [System.String] $PlaceAddress
    #TODO: Checklist and File
)

#Email validation
$EmailRegex = '^[_a-z0-9-]+(\.[_a-z0-9-]+)*@[a-z0-9-]+(\.[a-z0-9-]+)*(\.[a-z]{2,4})$'

Begin  {
    # Make sure things work here, if they don't, return nothing. Also set a timeout so that your command line doesn't lag.
    Try 
    {
        #Specify the pushbullet api key
        $ApiKey = ''
#        if ($ApiKey -eq '')
#        {
#            Write-Host " You do not have an API key defined.`r`n"'Place your API key at $ApiKey = '''' on line 80' -ForegroundColor Red
#            Exit
#        }
        #Convert api key into PSCredential object
        $Cred = New-Object System.Management.Automation.PSCredential ($ApiKey, (ConvertTo-SecureString $ApiKey -AsPlainText -Force))



        #Hash of names/iden of Devices and Contacts.
        $Destinations = @{}
        #Get list of registered devices
        $Devices = (Invoke-RestMethod -Method GET -Uri 'https://api.pushbullet.com/v2/devices' -Credential $Cred -DisableKeepAlive).devices

        foreach ($Device in $Devices)
        {
            if ($Device.active -eq 'True')
            {
                $Destinations.Add($Device.nickname, $Device.iden)
            }
        }

        #Get contacts for selection
        $Contacts = (Invoke-RestMethod -Method GET -Uri 'https://api.pushbullet.com/v2/contacts' -Credential $Cred -DisableKeepAlive).contacts

        foreach ($Dest in $Contacts)
        {
            if ($Dest.active -eq 'True')
            {
                $Destinations.Add($Dest.name, $Dest.email)
            }
        }
    }
    Catch
    {
        #Return
    }
}

Process
{
    #Build the push in a hastable (key/value for JSON)
    $Push = @{}

    #Need to know and set what kind of push this is since they take different parameters
    switch ($PSCmdlet.ParameterSetName)
    {
        'note'
        {
            $Push.Add('type', 'note')
        }
        'link' 
        {
            $Push.Add('type', 'link')
        }
        'address'
        {
            $Push.Add('type', 'address')
        }
    }

    #Set the push title, all have to have one
    $Push.Add('title', $Title)

    #Set the message, we don't always have to set one, just on notes
    if ($Message -ne '')
    {
        $Push.Add('body', $Message)
    }
    else
    {
        $Push.Add('body', '')
    }

    #Set the url for the link type
    if ($PSCmdlet.ParameterSetName -eq 'link')
    {
        $Link = [System.URI] $Link
        $Push.Add('url', $Link)
    }

    #Set the address type push
    if (($Placename -ne '') -and ($Placeaddress -ne ''))
    {
        $Push.Add('name', $Placename)
        $Push.Add('address', $Placeaddress)
    }

    #Using the $Contact variable to figure out if the destination in $Destinations is a Device/Contact or E-Mail address
    foreach ($Key in $Destinations.Keys)
    {
        if ($Key -like '*' + $Contact + '*')
        {
            if ($Destinations[$Key] -match $EmailRegex)
            {
                $Push.Add('email', $Destinations[$Key])
            }
            else
            {
                $Push.Add('device_iden', $Destinations[$Key])
            }
        }
        elseif ($Contact -match $EmailRegex)
        {
            $Push.Add('email', $Contact)
        }
    }
    #JSON formatting for the POST
    $Push = ConvertTo-Json $Push

    #Push the notification
    Invoke-RestMethod -Method POST -Uri 'https://api.pushbullet.com/v2/pushes' -Credential $Cred -Body $Push -ContentType 'application/json' -DisableKeepAlive
}
