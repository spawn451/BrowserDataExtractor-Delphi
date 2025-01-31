unit BrowserDetector;

interface

uses
  System.SysUtils, System.IOUtils;

type
  TBrowserInfo = record
    IsInstalled: Boolean;
    InstallPath: string;
  end;

  TBrowserDetector = class
  private
    FChromePath: string;
    FFirefoxPath: string;
    FBravePath: string;
    FEdgePath: string;
    function GetChromeInfo: TBrowserInfo;
    function GetFirefoxInfo: TBrowserInfo;
    function GetBraveInfo: TBrowserInfo;
    function GetEdgeInfo: TBrowserInfo;
  public
    constructor Create;
    property ChromeInfo: TBrowserInfo read GetChromeInfo;
    property FirefoxInfo: TBrowserInfo read GetFirefoxInfo;
    property BraveInfo: TBrowserInfo read GetBraveInfo;
    property EdgeInfo: TBrowserInfo read GetEdgeInfo;
    function IsChromeInstalled: Boolean;
    function IsFirefoxInstalled: Boolean;
    function IsBraveInstalled: Boolean;
    function IsEdgeInstalled: Boolean;
    class function GetBrowserName(IsChrome, IsFirefox, IsBrave, IsEdge: Boolean): string;
  end;

implementation

constructor TBrowserDetector.Create;
begin
  inherited;
  FChromePath := TPath.Combine(TPath.Combine(
    GetEnvironmentVariable('LOCALAPPDATA'),
    'Google\Chrome'));
  FFirefoxPath := TPath.Combine(TPath.Combine(
    GetEnvironmentVariable('APPDATA'),
    'Mozilla\Firefox'));
  FBravePath := TPath.Combine(TPath.Combine(
    GetEnvironmentVariable('LOCALAPPDATA'),
    'BraveSoftware\Brave-Browser'));
  FEdgePath := TPath.Combine(TPath.Combine(
    GetEnvironmentVariable('LOCALAPPDATA'),
    'Microsoft\Edge'));
end;

function TBrowserDetector.GetChromeInfo: TBrowserInfo;
begin
  Result.IsInstalled := DirectoryExists(FChromePath);
  Result.InstallPath := FChromePath;
end;

function TBrowserDetector.GetFirefoxInfo: TBrowserInfo;
begin
  Result.IsInstalled := DirectoryExists(FFirefoxPath);
  Result.InstallPath := FFirefoxPath;
end;

function TBrowserDetector.GetBraveInfo: TBrowserInfo;
begin
  Result.IsInstalled := DirectoryExists(FBravePath);
  Result.InstallPath := FBravePath;
end;

function TBrowserDetector.GetEdgeInfo: TBrowserInfo;
begin
  Result.IsInstalled := DirectoryExists(FEdgePath);
  Result.InstallPath := FEdgePath;
end;

function TBrowserDetector.IsChromeInstalled: Boolean;
begin
  Result := DirectoryExists(FChromePath);
end;

function TBrowserDetector.IsFirefoxInstalled: Boolean;
begin
  Result := DirectoryExists(FFirefoxPath);
end;

function TBrowserDetector.IsBraveInstalled: Boolean;
begin
  Result := DirectoryExists(FBravePath);
end;

function TBrowserDetector.IsEdgeInstalled: Boolean;
begin
  Result := DirectoryExists(FEdgePath);
end;

class function TBrowserDetector.GetBrowserName(IsChrome, IsFirefox, IsBrave, IsEdge: Boolean): string;
var
  InstalledBrowsers: TArray<string>;
begin
  SetLength(InstalledBrowsers, 0);
  if IsChrome then
    InstalledBrowsers := InstalledBrowsers + ['Chrome'];
  if IsFirefox then
    InstalledBrowsers := InstalledBrowsers + ['Firefox'];
  if IsBrave then
    InstalledBrowsers := InstalledBrowsers + ['Brave'];
  if IsEdge then
    InstalledBrowsers := InstalledBrowsers + ['Edge'];

  case Length(InstalledBrowsers) of
    0: Result := 'No supported browsers';
    1: Result := InstalledBrowsers[0];
    2: Result := InstalledBrowsers[0] + ', ' + InstalledBrowsers[1];
    3: Result := InstalledBrowsers[0] + ', ' + InstalledBrowsers[1] + ', ' + InstalledBrowsers[2];
    4: Result := InstalledBrowsers[0] + ', ' + InstalledBrowsers[1] + ', ' +
                InstalledBrowsers[2] + ', ' + InstalledBrowsers[3];
  end;
end;

end.
