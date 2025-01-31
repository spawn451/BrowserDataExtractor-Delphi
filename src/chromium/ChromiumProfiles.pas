unit ChromiumProfiles;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils;

type
  TBrowserKind = (bkChrome, bkBrave, bkEdge);  // Added Edge

  TChromiumProfile = record
    Name: string;
    Path: string;
  end;

  TChromiumProfiles = array of TChromiumProfile;

  TChromiumProfileHelper = class
  private
    FBrowserKind: TBrowserKind;
    function GetBrowserPath: string;
    function GetBrowserName: string;
  public
    constructor Create(ABrowserKind: TBrowserKind);
    function GetProfiles: TChromiumProfiles;
    procedure ListProfiles;
    function SelectProfile(ProfileChoice: Integer = 0): string;
  end;

implementation

constructor TChromiumProfileHelper.Create(ABrowserKind: TBrowserKind);
begin
  inherited Create;
  FBrowserKind := ABrowserKind;
end;

function TChromiumProfileHelper.GetBrowserPath: string;
begin
  case FBrowserKind of
    bkChrome:
      Result := TPath.Combine(TPath.Combine(
        GetEnvironmentVariable('LOCALAPPDATA'),
        'Google\Chrome\User Data'));
    bkBrave:
      Result := TPath.Combine(TPath.Combine(
        GetEnvironmentVariable('LOCALAPPDATA'),
        'BraveSoftware\Brave-Browser\User Data'));
    bkEdge:
      Result := TPath.Combine(TPath.Combine(
        GetEnvironmentVariable('LOCALAPPDATA'),
        'Microsoft\Edge\User Data'));
  end;
end;

function TChromiumProfileHelper.GetBrowserName: string;
begin
  case FBrowserKind of
    bkChrome:
      Result := 'chrome';
    bkBrave:
      Result := 'brave';
    bkEdge:
      Result := 'edge';
  end;
end;

function TChromiumProfileHelper.GetProfiles: TChromiumProfiles;
var
  BrowserDir: string;
  ProfileDirs: TArray<string>;
  ProfileName: string;
begin
  SetLength(Result, 0);
  BrowserDir := GetBrowserPath;

  if not DirectoryExists(BrowserDir) then
  begin
    WriteLn(Format('%s directory not found at: %s', [GetBrowserName, BrowserDir]));
    Exit;
  end;

  // Add default profile first
  if DirectoryExists(TPath.Combine(BrowserDir, 'Default')) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := 'Default';
    Result[High(Result)].Path := TPath.Combine(BrowserDir, 'Default');
  end;

  // Get additional profiles
  ProfileDirs := TDirectory.GetDirectories(BrowserDir, 'Profile *');
  for var Dir in ProfileDirs do
  begin
    ProfileName := ExtractFileName(Dir);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := ProfileName;
    Result[High(Result)].Path := Dir;
  end;
end;

procedure TChromiumProfileHelper.ListProfiles;
var
  Profiles: TChromiumProfiles;
begin
  Profiles := GetProfiles;
  if Length(Profiles) = 0 then
  begin
    WriteLn(Format('No %s profiles found.', [GetBrowserName]));
    Exit;
  end;

  WriteLn(Format('Available %s profiles:', [GetBrowserName]));
  for var i := 0 to High(Profiles) do
    WriteLn(i + 1, ' -> ', Profiles[i].Name);
end;

function TChromiumProfileHelper.SelectProfile(ProfileChoice: Integer = 0): string;
var
  Profiles: TChromiumProfiles;
  input: string;
begin
  Result := '';
  Profiles := GetProfiles;

  if Length(Profiles) = 0 then
  begin
    WriteLn(Format('No %s profiles found.', [GetBrowserName]));
    Exit;
  end;

  if (ProfileChoice > 0) and (ProfileChoice <= Length(Profiles)) then
  begin
    Result := Profiles[ProfileChoice - 1].Path;
    Exit;
  end;

  WriteLn(Format('Select the %s profile:', [GetBrowserName]));
  for var i := 0 to High(Profiles) do
    WriteLn(i + 1, ' -> ', Profiles[i].Name);

  while True do
  begin
    Write('Profile number (1-', Length(Profiles), '): ');
    ReadLn(input);
    if TryStrToInt(input, ProfileChoice) and
       (ProfileChoice >= 1) and (ProfileChoice <= Length(Profiles)) then
    begin
      Result := Profiles[ProfileChoice - 1].Path;
      Break;
    end;
    WriteLn('Invalid selection. Please try again.');
  end;
end;

end.