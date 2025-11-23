Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'

# Function to create a custom password prompt
function Get-Password {
    $passwordForm = New-Object System.Windows.Forms.Form
    $passwordForm.Text = 'Enter Password'
    $passwordForm.Size = New-Object System.Drawing.Size(300, 150)
    $passwordForm.StartPosition = 'CenterScreen'
    $passwordForm.FormBorderStyle = 'FixedDialog'
    $passwordForm.MaximizeBox = $false
    $passwordForm.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $passwordForm.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    # Add a label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter a password for the .pfx file:"
    $label.Location = New-Object System.Drawing.Point(10, 20)
    $label.Size = New-Object System.Drawing.Size(280, 20)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $passwordForm.Controls.Add($label)

    # Add a textbox for password input
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 50)
    $textBox.Size = New-Object System.Drawing.Size(260, 26)
    $textBox.PasswordChar = '*' # Mask the password input
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $passwordForm.Controls.Add($textBox)

    # Add an OK button
    $buttonOK = New-Object System.Windows.Forms.Button
    $buttonOK.Text = 'OK'
    $buttonOK.Location = New-Object System.Drawing.Point(100, 80)
    $buttonOK.Size = New-Object System.Drawing.Size(80, 30)
    $buttonOK.BackColor = [System.Drawing.Color]::FromArgb(0, 123, 255)
    $buttonOK.ForeColor = [System.Drawing.Color]::White
    $buttonOK.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $buttonOK.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $buttonOK.FlatAppearance.BorderSize = 0
    $buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $passwordForm.AcceptButton = $buttonOK
    $passwordForm.Controls.Add($buttonOK)

    # Show the form and return the password
    if ($passwordForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    }
    return $null
}

# Function to open a folder browser dialog for export path
function Get-ExportPath {
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select a folder to save the certificate files"
    $folderBrowser.RootFolder = [System.Environment+SpecialFolder]::Desktop

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $folderBrowser.SelectedPath
    }
    return $null
}

# Create the Form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Certificate Generation'
$form.Size = New-Object System.Drawing.Size(800, 600) # Adjusted size for better layout
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250) # Light gray background
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10) # Modern font

# Gradient background for the form
$form.Add_Paint({
        $gradientBrush = New-Object Drawing.Drawing2D.LinearGradientBrush(
            $form.ClientRectangle,
            [System.Drawing.Color]::FromArgb(250, 250, 250), # Light gray
            [System.Drawing.Color]::FromArgb(250, 250, 250), # Light blue
            [Drawing.Drawing2D.LinearGradientMode]::Vertical
        )
        $_.Graphics.FillRectangle($gradientBrush, $form.ClientRectangle)
    })

# Create a function to add consistent labels and textboxes
function Add-FormControl {
    param (
        [string]$LabelText,
        [int]$YPosition,
        [string]$DefaultValue = ""
    )
    # Label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $LabelText
    $label.Location = New-Object System.Drawing.Point(20, $YPosition)
    $label.Size = New-Object System.Drawing.Size(150, 20)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $label.BackColor = [System.Drawing.Color]::Transparent # Make label background transparent
    $form.Controls.Add($label)

    # TextBox
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(180, $YPosition)
    $textBox.Size = New-Object System.Drawing.Size(230, 26)
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $textBox.BackColor = [System.Drawing.Color]::White # Set textbox background to white
    $textBox.Text = $DefaultValue
    $form.Controls.Add($textBox)

    return $textBox
}

# Add input fields with reduced spacing
$textSubject = Add-FormControl -LabelText "Subject Name:" -YPosition 20 -DefaultValue $([System.Net.Dns]::GetHostByName($ENV:COMPUTERNAME).HostName).ToLower()
$textFriendlyName = Add-FormControl -LabelText "Friendly Name:" -YPosition 60 -DefaultValue ([System.Net.Dns]::GetHostName()).ToLower()
$textOrganization = Add-FormControl -LabelText "Organization:" -YPosition 100 -DefaultValue "My Organization"
$textOrgUnit = Add-FormControl -LabelText "Org Unit:" -YPosition 140 -DefaultValue "Department"
$textEmail = Add-FormControl -LabelText "Email:" -YPosition 180 -DefaultValue "admin@example.com"
$textLocation = Add-FormControl -LabelText "Location:" -YPosition 220
$textCountry = Add-FormControl -LabelText "Country:" -YPosition 260 -DefaultValue ([System.Globalization.CultureInfo]::CurrentCulture.Name.Split('-')[1])

# Add ComboBox for Certificate Years
$labelYears = New-Object System.Windows.Forms.Label
$labelYears.Text = 'Certificate Years:'
$labelYears.Location = New-Object System.Drawing.Point(20, 300)
$labelYears.Size = New-Object System.Drawing.Size(150, 20)
$labelYears.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$labelYears.BackColor = [System.Drawing.Color]::Transparent # Make label background transparent
$form.Controls.Add($labelYears)

$comboYears = New-Object System.Windows.Forms.ComboBox
$comboYears.Location = New-Object System.Drawing.Point(180, 300)
$comboYears.Size = New-Object System.Drawing.Size(230, 26)
$comboYears.DropDownStyle = 'DropDownList'
$comboYears.Items.AddRange(@("1", "2", "3", "5", "10"))
$comboYears.SelectedIndex = 0
$comboYears.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250) # Light gray background
$comboYears.ForeColor = [System.Drawing.Color]::Black # Black text
$form.Controls.Add($comboYears)

# Add a single textbox for DNS names
$textDNSNames = Add-FormControl -LabelText "DNS Names (comma-separated):" -YPosition 340 -DefaultValue $([System.Net.Dns]::GetHostByName($ENV:COMPUTERNAME).HostName).ToLower()

# Add ComboBox for Certificate Store Location
$labelStoreLocation = New-Object System.Windows.Forms.Label
$labelStoreLocation.Text = 'Certificate Store:'
$labelStoreLocation.Location = New-Object System.Drawing.Point(20, 380)
$labelStoreLocation.Size = New-Object System.Drawing.Size(150, 20)
$labelStoreLocation.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$labelStoreLocation.BackColor = [System.Drawing.Color]::Transparent # Make label background transparent
$form.Controls.Add($labelStoreLocation)

$comboStoreLocation = New-Object System.Windows.Forms.ComboBox
$comboStoreLocation.Location = New-Object System.Drawing.Point(180, 380)
$comboStoreLocation.Size = New-Object System.Drawing.Size(230, 26)
$comboStoreLocation.DropDownStyle = 'DropDownList'
$comboStoreLocation.Items.AddRange(@("Cert:\CurrentUser\My", "Cert:\LocalMachine\My", "Cert:\LocalMachine\Root"))
$comboStoreLocation.SelectedIndex = 0
$comboStoreLocation.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250) # Light gray background
$comboStoreLocation.ForeColor = [System.Drawing.Color]::Black # Black text
$form.Controls.Add($comboStoreLocation)

# Add CheckBox for Export
$checkBoxExport = New-Object System.Windows.Forms.CheckBox
$checkBoxExport.Text = "Export Certificate"
$checkBoxExport.Location = New-Object System.Drawing.Point(20, 410)
$checkBoxExport.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxExport.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxExport.BackColor = [System.Drawing.Color]::Transparent # Make checkbox background transparent
$form.Controls.Add($checkBoxExport)

# Add a status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object System.Drawing.Point(20, 430)
$statusLabel.Size = New-Object System.Drawing.Size(400, 20)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$statusLabel.BackColor = [System.Drawing.Color]::Transparent # Make label background transparent
$form.Controls.Add($statusLabel)

# Add a progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(22, 450)
$progressBar.Size = New-Object System.Drawing.Size(400, 20)
$progressBar.Style = 'Continuous'
$progressBar.BackColor = [System.Drawing.Color]::White # Set progress bar background to white
$form.Controls.Add($progressBar)

# Add a modern Submit Button
$buttonSubmit = New-Object System.Windows.Forms.Button
$buttonSubmit.Text = 'Generate Certificate'
$buttonSubmit.Location = New-Object System.Drawing.Point(20, 480)
$buttonSubmit.Size = New-Object System.Drawing.Size(400, 40)
$buttonSubmit.BackColor = [System.Drawing.Color]::FromArgb(0, 123, 255) # Blue color
$buttonSubmit.ForeColor = [System.Drawing.Color]::White
$buttonSubmit.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$buttonSubmit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$buttonSubmit.FlatAppearance.BorderSize = 0
$buttonSubmit.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($buttonSubmit)

# Create a group panel for Text Extensions
$groupTextExtensions = New-Object System.Windows.Forms.GroupBox
$groupTextExtensions.Text = "Text Extensions"
$groupTextExtensions.Location = New-Object System.Drawing.Point(450, 20)
$groupTextExtensions.Size = New-Object System.Drawing.Size(320, 220)
$groupTextExtensions.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$groupTextExtensions.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250) # Light gray background
$form.Controls.Add($groupTextExtensions)

# Add CheckBoxes for Text Extensions inside the group panel
$checkBoxClientAuth = New-Object System.Windows.Forms.CheckBox
$checkBoxClientAuth.Text = "Client Authentication (1.3.6.1.5.5.7.3.2)"
$checkBoxClientAuth.Location = New-Object System.Drawing.Point(10, 30)
$checkBoxClientAuth.Size = New-Object System.Drawing.Size(300, 20)
$checkBoxClientAuth.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxClientAuth.BackColor = [System.Drawing.Color]::Transparent
$groupTextExtensions.Controls.Add($checkBoxClientAuth)

$checkBoxServerAuth = New-Object System.Windows.Forms.CheckBox
$checkBoxServerAuth.Text = "Server Authentication (1.3.6.1.5.5.7.3.1)"
$checkBoxServerAuth.Location = New-Object System.Drawing.Point(10, 60)
$checkBoxServerAuth.Size = New-Object System.Drawing.Size(300, 20)
$checkBoxServerAuth.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxServerAuth.BackColor = [System.Drawing.Color]::Transparent
$groupTextExtensions.Controls.Add($checkBoxServerAuth)

$checkBoxSecureEmail = New-Object System.Windows.Forms.CheckBox
$checkBoxSecureEmail.Text = "Secure Email (1.3.6.1.5.5.7.3.4)"
$checkBoxSecureEmail.Location = New-Object System.Drawing.Point(10, 90)
$checkBoxSecureEmail.Size = New-Object System.Drawing.Size(300, 20)
$checkBoxSecureEmail.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxSecureEmail.BackColor = [System.Drawing.Color]::Transparent
$groupTextExtensions.Controls.Add($checkBoxSecureEmail)

$checkBoxCodeSigning = New-Object System.Windows.Forms.CheckBox
$checkBoxCodeSigning.Text = "Code Signing (1.3.6.1.5.5.7.3.3)"
$checkBoxCodeSigning.Location = New-Object System.Drawing.Point(10, 120)
$checkBoxCodeSigning.Size = New-Object System.Drawing.Size(300, 20)
$checkBoxCodeSigning.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxCodeSigning.BackColor = [System.Drawing.Color]::Transparent
$groupTextExtensions.Controls.Add($checkBoxCodeSigning)

$checkBoxTimestampSigning = New-Object System.Windows.Forms.CheckBox
$checkBoxTimestampSigning.Text = "Timestamp Signing (1.3.6.1.5.5.7.3.8)"
$checkBoxTimestampSigning.Location = New-Object System.Drawing.Point(10, 150)
$checkBoxTimestampSigning.Size = New-Object System.Drawing.Size(300, 20)
$checkBoxTimestampSigning.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxTimestampSigning.BackColor = [System.Drawing.Color]::Transparent
$groupTextExtensions.Controls.Add($checkBoxTimestampSigning)

$checkBoxAllPurposes = New-Object System.Windows.Forms.CheckBox
$checkBoxAllPurposes.Text = "All Purposes"
$checkBoxAllPurposes.Location = New-Object System.Drawing.Point(10, 180)
$checkBoxAllPurposes.Size = New-Object System.Drawing.Size(300, 20)
$checkBoxAllPurposes.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxAllPurposes.BackColor = [System.Drawing.Color]::Transparent
$groupTextExtensions.Controls.Add($checkBoxAllPurposes)

# Set "All Purposes" as checked by default
$checkBoxAllPurposes.Checked = $true

# Add event handlers to the other checkboxes in the "Text Extensions" group
$checkBoxClientAuth.Add_CheckedChanged({
        if ($checkBoxClientAuth.Checked) {
            $checkBoxAllPurposes.Checked = $false
        }
    })

$checkBoxServerAuth.Add_CheckedChanged({
        if ($checkBoxServerAuth.Checked) {
            $checkBoxAllPurposes.Checked = $false
        }
    })

$checkBoxSecureEmail.Add_CheckedChanged({
        if ($checkBoxSecureEmail.Checked) {
            $checkBoxAllPurposes.Checked = $false
        }
    })

$checkBoxCodeSigning.Add_CheckedChanged({
        if ($checkBoxCodeSigning.Checked) {
            $checkBoxAllPurposes.Checked = $false
        }
    })

$checkBoxTimestampSigning.Add_CheckedChanged({
        if ($checkBoxTimestampSigning.Checked) {
            $checkBoxAllPurposes.Checked = $false
        }
    })

# Add an event handler to the "All Purposes" checkbox
$checkBoxAllPurposes.Add_CheckedChanged({
        if ($checkBoxAllPurposes.Checked) {
            # Clear all other checkboxes in the Text Extensions group
            $checkBoxClientAuth.Checked = $false
            $checkBoxServerAuth.Checked = $false
            $checkBoxSecureEmail.Checked = $false
            $checkBoxCodeSigning.Checked = $false
            $checkBoxTimestampSigning.Checked = $false
        }
    })

# Create a group panel for Key Usage
$groupKeyUsage = New-Object System.Windows.Forms.GroupBox
$groupKeyUsage.Text = "Key Usage"
$groupKeyUsage.Location = New-Object System.Drawing.Point(450, 250)
$groupKeyUsage.Size = New-Object System.Drawing.Size(320, 200)
$groupKeyUsage.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$groupKeyUsage.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250) # Light gray background
$form.Controls.Add($groupKeyUsage)

# Add CheckBoxes for Key Usage inside the group panel
$checkBoxCertSign = New-Object System.Windows.Forms.CheckBox
$checkBoxCertSign.Text = "CertSign"
$checkBoxCertSign.Location = New-Object System.Drawing.Point(10, 30)
$checkBoxCertSign.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxCertSign.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxCertSign.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxCertSign)

$checkBoxCRLSign = New-Object System.Windows.Forms.CheckBox
$checkBoxCRLSign.Text = "CRLSign"
$checkBoxCRLSign.Location = New-Object System.Drawing.Point(10, 60)
$checkBoxCRLSign.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxCRLSign.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxCRLSign.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxCRLSign)

$checkBoxDataEncipherment = New-Object System.Windows.Forms.CheckBox
$checkBoxDataEncipherment.Text = "DataEncipherment"
$checkBoxDataEncipherment.Location = New-Object System.Drawing.Point(10, 90)
$checkBoxDataEncipherment.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxDataEncipherment.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxDataEncipherment.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxDataEncipherment)

$checkBoxDecipherOnly = New-Object System.Windows.Forms.CheckBox
$checkBoxDecipherOnly.Text = "DecipherOnly"
$checkBoxDecipherOnly.Location = New-Object System.Drawing.Point(10, 120)
$checkBoxDecipherOnly.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxDecipherOnly.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxDecipherOnly.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxDecipherOnly)

$checkBoxDigitalSignature = New-Object System.Windows.Forms.CheckBox
$checkBoxDigitalSignature.Text = "DigitalSignature"
$checkBoxDigitalSignature.Location = New-Object System.Drawing.Point(10, 150)
$checkBoxDigitalSignature.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxDigitalSignature.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxDigitalSignature.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxDigitalSignature)

$checkBoxEncipherOnly = New-Object System.Windows.Forms.CheckBox
$checkBoxEncipherOnly.Text = "EncipherOnly"
$checkBoxEncipherOnly.Location = New-Object System.Drawing.Point(160, 30)
$checkBoxEncipherOnly.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxEncipherOnly.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxEncipherOnly.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxEncipherOnly)

$checkBoxKeyAgreement = New-Object System.Windows.Forms.CheckBox
$checkBoxKeyAgreement.Text = "KeyAgreement"
$checkBoxKeyAgreement.Location = New-Object System.Drawing.Point(160, 60)
$checkBoxKeyAgreement.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxKeyAgreement.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxKeyAgreement.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxKeyAgreement)

$checkBoxKeyEncipherment = New-Object System.Windows.Forms.CheckBox
$checkBoxKeyEncipherment.Text = "KeyEncipherment"
$checkBoxKeyEncipherment.Location = New-Object System.Drawing.Point(160, 90)
$checkBoxKeyEncipherment.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxKeyEncipherment.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxKeyEncipherment.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxKeyEncipherment)

$checkBoxNonRepudiation = New-Object System.Windows.Forms.CheckBox
$checkBoxNonRepudiation.Text = "NonRepudiation"
$checkBoxNonRepudiation.Location = New-Object System.Drawing.Point(160, 120)
$checkBoxNonRepudiation.Size = New-Object System.Drawing.Size(150, 20)
$checkBoxNonRepudiation.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$checkBoxNonRepudiation.BackColor = [System.Drawing.Color]::Transparent
$groupKeyUsage.Controls.Add($checkBoxNonRepudiation)

# Set default key usages
$checkBoxDigitalSignature.Checked = $true
$checkBoxKeyEncipherment.Checked = $true
$checkBoxDataEncipherment.Checked = $true
$checkBoxCertSign.Checked = $true

# Event handler for form load
$form.Add_Load({
        try {
            # Attempt to retrieve the city information from ipinfo.io
            $ipInfo = Invoke-RestMethod -Uri "http://ipinfo.io/json"
            $textLocation.Text = $ipInfo.city
        }
        catch {
            # If an error occurs, set city to null and log the error
            $textLocation.Text = "Unknown"
        }
    })

$buttonSubmit.Add_Click({
        try {
            # Validate required fields
            if ([string]::IsNullOrEmpty($textSubject.Text) -or
                [string]::IsNullOrEmpty($textOrganization.Text) -or
                [string]::IsNullOrEmpty($textCountry.Text)) {
                [System.Windows.Forms.MessageBox]::Show("Please fill in all required fields.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK)
                return
            }

            # Update status label and show progress
            $statusLabel.Text = "Generating certificate..."
            $statusLabel.ForeColor = [System.Drawing.Color]::Blue
            $progressBar.Value = 30

            # Retrieve user input values
            $subject = $textSubject.Text
            $FriendlyName = $textFriendlyName.Text
            $Organization = $textOrganization.Text
            $OrgUnit = $textOrgUnit.Text
            $emailSettings = $textEmail.Text
            $Location = $textLocation.Text
            $Country = $textCountry.Text
            $years = $comboYears.SelectedItem
            $dnsNames = $textDNSNames.Text -split ',' | ForEach-Object { $_.Trim() } # Split and trim DNS names
            $storeLocation = $comboStoreLocation.SelectedItem

            Import-Module PKI | Out-Null
            # Build the certificate parameters
            $params = @{
                Type              = 'Custom'
                Subject           = "CN=$subject, O=$Organization, OU=$OrgUnit, E=$emailSettings, L=$Location, C=$Country"
                FriendlyName      = $FriendlyName
                HashAlgorithm     = "SHA256"
                KeyLength         = 2048
                KeyAlgorithm      = "RSA"
                NotAfter          = (Get-Date).AddYears([int]$years)
                CertStoreLocation = $storeLocation
                DnsName           = $dnsNames # Use the array of DNS names
                KeyExportPolicy   = 'Exportable'
            }

            # Add Basic Constraints extension (always included)
            $textExtensions = @(
                "2.5.29.19={text}CA=true&PathLength=0" # Basic Constraints: Subject Type=CA, Path Length Constraint=0
            )

            # Add Enhanced Key Usage (EKU) extensions based on selected checkboxes
            $ekuExtensions = @()
            if ($checkBoxClientAuth.Checked) {
                $ekuExtensions += "1.3.6.1.5.5.7.3.2" # Client Authentication
            }
            if ($checkBoxServerAuth.Checked) {
                $ekuExtensions += "1.3.6.1.5.5.7.3.1" # Server Authentication
            }
            if ($checkBoxSecureEmail.Checked) {
                $ekuExtensions += "1.3.6.1.5.5.7.3.4" # Secure Email
            }
            if ($checkBoxCodeSigning.Checked) {
                $ekuExtensions += "1.3.6.1.5.5.7.3.3" # Code Signing
            }
            if ($checkBoxTimestampSigning.Checked) {
                $ekuExtensions += "1.3.6.1.5.5.7.3.8" # Timestamp Signing
            }

            # Add Enhanced Key Usage (EKU) extension only if any EKU options are selected
            if ($ekuExtensions.Count -gt 0) {
                $textExtensions += "2.5.29.37={text}$($ekuExtensions -join ',')" # Enhanced Key Usage
            }

            # Add Text Extensions to the parameters
            $params.TextExtension = $textExtensions

            # Add Key Usage based on selected checkboxes
            $keyUsage = @()
            if ($checkBoxCertSign.Checked) {
                $keyUsage += "CertSign"
            }
            if ($checkBoxCRLSign.Checked) {
                $keyUsage += "CRLSign"
            }
            if ($checkBoxDataEncipherment.Checked) {
                $keyUsage += "DataEncipherment"
            }
            if ($checkBoxDecipherOnly.Checked) {
                $keyUsage += "DecipherOnly"
            }
            if ($checkBoxDigitalSignature.Checked) {
                $keyUsage += "DigitalSignature"
            }
            if ($checkBoxEncipherOnly.Checked) {
                $keyUsage += "EncipherOnly"
            }
            if ($checkBoxKeyAgreement.Checked) {
                $keyUsage += "KeyAgreement"
            }
            if ($checkBoxKeyEncipherment.Checked) {
                $keyUsage += "KeyEncipherment"
            }
            if ($checkBoxNonRepudiation.Checked) {
                $keyUsage += "NonRepudiation"
            }

            # Add Key Usage to the parameters if any are selected
            if ($keyUsage.Count -gt 0) {
                $params.KeyUsage = $keyUsage
            }

            # Generate the certificate
            $Certificate = New-SelfSignedCertificate @params

            # Export the certificate if the checkbox is checked
            if ($checkBoxExport.Checked) {
                # Prompt the user for a password using the custom dialog
                $password = Get-Password
                if (-not $password) {
                    [System.Windows.Forms.MessageBox]::Show("Password is required for export.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK)
                    return
                }

                # Prompt the user for an export path
                $FilePath = Get-ExportPath
                if (-not $FilePath) {
                    [System.Windows.Forms.MessageBox]::Show("Export path is required.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK)
                    return
                }

                # Convert the password to a secure string
                $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force

                # Define the certificate name based on the Subject Name
                $CertificateName = $subject -replace '[^\w\-]', '_' # Replace invalid characters with underscores

                # Export the certificate to a .pfx file
                Export-PfxCertificate -Cert $Certificate -FilePath "$FilePath\$CertificateName.pfx" -Password $securePassword

                # Export the certificate to a .cer file
                Export-Certificate -Cert $Certificate -FilePath "$FilePath\$CertificateName.cer"

                Write-Output "Certificate exported to: $FilePath"
            }

            # Update progress and status label
            $progressBar.Value = 100
            $statusLabel.Text = "Certificate generated successfully!"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            [System.Windows.Forms.MessageBox]::Show('Certificate generated successfully!', 'Success', [System.Windows.Forms.MessageBoxButtons]::OK)
            $form.Close()
        }
        catch {
            # Update status label and show error message
            $progressBar.Value = 0
            $statusLabel.Text = "Error: $_"
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.MessageBox]::Show("An error occurred while generating the certificate: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK)
        }
    })

# Show the form
$form.ShowDialog() | Out-Null