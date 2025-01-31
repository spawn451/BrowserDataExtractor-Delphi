unit FirefoxProfiles;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.IOUtils;

type
  TFirefoxProfile = record
    Name: string;
    Path: string;
  end;
  TFirefoxProfiles = array of TFirefoxProfile;

function GetFirefoxProfiles: TFirefoxProfiles;
procedure ListProfiles;
function SelectProfile(ProfileChoice: Integer = 0): string;

implementation

function GetFirefoxProfiles: TFirefoxProfiles;
var
  IniFile: TIniFile;
  IniPath: string;
  Sections: TStringList;
  i: Integer;
  ProfilePath: string;
begin
  SetLength(Result, 0);
  IniPath := TPath.Combine(GetEnvironmentVariable('APPDATA'),
    'Mozilla\Firefox\profiles.ini');

  if not FileExists(IniPath) then
  begin
    WriteLn('profiles.ini not found at: ', IniPath);
    Exit;
  end;

  Sections := TStringList.Create;
  IniFile := TIniFile.Create(IniPath);
  try
    IniFile.ReadSections(Sections);
    for i := 0 to Sections.Count - 1 do
    begin
      if Copy(Sections[i], 1, 7) = 'Profile' then
      begin
        ProfilePath := IniFile.ReadString(Sections[i], 'Path', '');
        if ProfilePath <> '' then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)].Name := ProfilePath;
          // Fix path separator
          ProfilePath := StringReplace(ProfilePath, '/', '\', [rfReplaceAll]);
          Result[High(Result)].Path := TPath.Combine(ExtractFilePath(IniPath),
            ProfilePath);
        end;
      end;
    end;
  finally
    IniFile.Free;
    Sections.Free;
  end;
end;


procedure ListProfiles;
var
  Profiles: TFirefoxProfiles;
  i: Integer;
begin
  Profiles := GetFirefoxProfiles;
  if Length(Profiles) = 0 then
  begin
    WriteLn('No Firefox profiles found.');
    Exit;
  end;

  WriteLn('Available Firefox profiles:');
  for i := 0 to High(Profiles) do
    WriteLn(i + 1, ' -> ', Profiles[i].Name);
end;

function SelectProfile(ProfileChoice: Integer = 0): string;
var
  Profiles: TFirefoxProfiles;
  input: string;
begin
  Result := '';
  Profiles := GetFirefoxProfiles;

  if Length(Profiles) = 0 then
  begin
    WriteLn('No Firefox profiles found.');
    Exit;
  end;

  if (ProfileChoice > 0) and (ProfileChoice <= Length(Profiles)) then
  begin
    Result := Profiles[ProfileChoice - 1].Path;
    Exit;
  end;

  WriteLn('Select the Mozilla profile:');
  for var i := 0 to High(Profiles) do
    WriteLn(i + 1, ' -> ', Profiles[i].Name);

  while True do
  begin
    Write('Profile number (1-', Length(Profiles), '): ');
    ReadLn(input);
    if TryStrToInt(input, ProfileChoice) and (ProfileChoice >= 1) and
      (ProfileChoice <= Length(Profiles)) then
    begin
      Result := Profiles[ProfileChoice - 1].Path;
      Break;
    end;
    WriteLn('Invalid selection. Please try again.');
  end;
end;

end.
