function ConvertTo-AV1Video {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [Parameter()]
        [string[]]
        $Filter = @('.mkv', '.webm', '.mp4', '.m4v', '.m4a', '.avi', '.mov', '.qt', '.ogv', '.ogg'),

        [Parameter(ParameterSetName = 'SpecificConfig')]
        [int]
        $VideoQuality = 35, # Default AV1 crf

        [Parameter(ParameterSetName = 'SpecificConfig')]
        [int]
        $VideoPreset = 10, # Default AV1 preset

        [Parameter(ParameterSetName = 'SpecificConfig')]
        [int]
        $AudioBitrate = 96, # Default OPUS preset

        [Parameter(ParameterSetName = 'PresetConfig')]
        [ValidateSet('Standard', 'High')]
        [string]
        $Preset = 'Standard',

        [Parameter()]
        [switch]
        $PreserveStructure,

        [Parameter()]
        [switch]
        $NoCrop
    )

    begin {
        Set-StrictMode -Version 3

        # Test if external commands are available
        if ($null -eq (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)) { throw 'Error: Cannot find ffmpeg on system PATH' }
        if ($null -eq (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)) { throw 'Error: Cannot find ffprobe on system PATH' }

        # Ensure input & output locations exist - if the output is a directory, create it if it doesn't exist
        # This isn't needed for files - ffmpeg will create those on its own
        if (-not (Test-Path $Path)) { throw "Error: Cannot find path '$Path' because it does not exist" }
        if (Test-Path $Destination -PathType Container) { $IsDirectory = $true }
        elseif ((Split-Path $Destination -Extension) -eq "") {
            $IsDirectory = $true
            try { New-Item -Path $Destination -ItemType Directory | Out-Null }
            catch { throw 'Error: Failed to create media output path.' }
        }
        else { $IsDirectory = $false }

        # Handle preset, if configured
        if ($null -ne $Preset) {
            switch ($Preset) {
                'High' {
                    $VideoQuality = 27
                    $VideoPreset = 6
                    $AudioBitrate = 128
                }
                Default {
                    $VideoQuality = 33
                    $VideoPreset = 10
                    $AudioBitrate = 96
                }
            }
        }

        # Process input
        $Files = Get-ChildItem -Path $Path -Recurse -File | Where-Object Extension -In $Filter
        $AudioBitrate = $AudioBitrate * 1000 # Convert to kilobits/s

        # Handles SVT_LOG environment variable - used to block SVT-AV1's output
        $SVTConfigPath = Join-Path 'env:' 'SVT_LOG'
        $SVTConfig = Test-Path $SVTConfigPath
        if ($SVTConfig) { $SVTValue = Get-Item $SVTConfigPath | Select-Object -ExpandProperty Value }
        $env:SVT_LOG = 1
    }

    process {
        foreach ($File in $Files) {
            if ($IsDirectory -and $PreserveStructure) { $Target = Join-Path $Destination $File.Directory.FullName.Substring($Path.Length) }
            elseif ($IsDirectory) { $Target = Join-Path $Destination $File.Name }
            else { $Target = $Destination }

            # Skip if target file already exists
            if (Test-Path $Target) {
                Write-Error -Message "Error: Path '$Target' exists, skipping..."
                Continue
            }

            # Detect cropping values
            # if (!$NoCrop) {
            #     $CropData & ffmpeg -skip_frame nokey -y -hide_banner -nostats -i $File -vf cropdetect -an -f null - 2>&1
            #     $Crop = ($CropData | Select-String -Pattern 'crop=.*' | Select-Object -Last 1 ).Matches.Value
            # }

            $FFMpegParams = @(
                '-i', $File.FullName,
                '-c:v', 'libsvtav1',
                '-crf', $VideoQuality,
                '-preset', $VideoPreset,
                '-c:a', 'libopus',
                '-b:a', $AudioBitrate,
                # '-vf', $Crop
                $Target
            )

            & ffmpeg @FFMpegParams -loglevel quiet -stats
        }
    }

    end {
        if ($SVTConfig) { $env:SVT_LOG = $SVTValue }
        else { Remove-Item $SVTConfigPath }
    }
}
