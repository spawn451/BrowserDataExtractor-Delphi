unit ChromiumExtension;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.StrUtils;

type
  TBrowserKind = (bkChrome, bkBrave, bkEdge);

  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TExtensionItem = record
    ID: string;
    URL: string;
    Enabled: Boolean;
    Name: string;
    Description: string;
    Version: string;
    HomepageURL: string;
  end;

  TExtensionItems = TArray<TExtensionItem>;

  TChromiumExtensionHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;

    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Extensions: TExtensionItems);
    procedure OutputJSON(const Extensions: TExtensionItems);
    procedure OutputCSV(const Extensions: TExtensionItems);
    procedure OutputExtensions(const Extensions: TExtensionItems);
    function GetExtensionObject(const JsonObj: TJSONObject; const Path: string)
      : TJSONObject;
  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetExtensions: TExtensionItems;
    function GetExtensionCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TChromiumExtensionHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, ' ', '_', [rfReplaceAll]);
end;

function TChromiumExtensionHelper.GetBrowserPrefix: string;
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

function TChromiumExtensionHelper.GetExtensionObject(const JsonObj: TJSONObject;
  const Path: string): TJSONObject;
var
  Parts: TArray<string>;
  Current: TJSONObject;
begin
  Result := nil;
  Parts := Path.Split(['.']);
  Current := JsonObj;

  for var Part in Parts do
  begin
    if not Assigned(Current) then
      Exit;
    var
    Value := Current.GetValue(Part);
    if not(Value is TJSONObject) then
      Exit;
    Current := Value as TJSONObject;
  end;
  Result := Current;
end;

function TChromiumExtensionHelper.GetExtensions: TExtensionItems;
var
  PreferencesFile: string;
  JSONContent: TJSONObject;
  ExtObj: TJSONObject;
begin
  SetLength(Result, 0);
  PreferencesFile := TPath.Combine(FProfilePath, 'Secure Preferences');
  if not FileExists(PreferencesFile) then
    Exit;

  try
    JSONContent := TJSONObject.ParseJSONValue(TFile.ReadAllText(PreferencesFile)
      ) as TJSONObject;
    if not Assigned(JSONContent) then
      Exit;

    try
      // Try different paths
      var
      SettingsPaths := TArray<string>.Create('settings.extensions',
        'settings.settings', 'extensions.settings');

      ExtObj := nil;
      for var Path in SettingsPaths do
      begin
        ExtObj := GetExtensionObject(JSONContent, Path);
        if Assigned(ExtObj) then
          Break;
      end;

      if not Assigned(ExtObj) then
        Exit;

      // Process extensions like in Go code
      for var Pair in ExtObj do
      begin
        var
        ExtData := TJSONObject(Pair.JsonValue);
        var
        ExtId := Pair.JsonString.Value;

        // Check location
        var
          Location: TJSONNumber;
        if ExtData.TryGetValue<TJSONNumber>('location', Location) then
        begin
          if Location.AsInt in [5, 10] then
            Continue;
        end;

        // Check if disabled
        var
        Enabled := not Assigned(ExtData.GetValue('disable_reasons'));

        // Get manifest
        var
          Manifest: TJSONObject;
        if not ExtData.TryGetValue<TJSONObject>('manifest', Manifest) then
        begin
          SetLength(Result, Length(Result) + 1);
          with Result[High(Result)] do
          begin
            ID := ExtId;
            Enabled := Enabled;
            var
            PathValue := ExtData.GetValue('path');
            if Assigned(PathValue) then
              Name := PathValue.Value;
          end;
          Continue;
        end;

        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          ID := ExtId;

          var
          UpdateURL := '';
          var
          UpdateValue := Manifest.GetValue('update_url');
          if Assigned(UpdateValue) then
            UpdateURL := UpdateValue.Value;

          if Pos('clients2.google.com/service/update2/crx', UpdateURL) > 0 then
            URL := 'https://Chromium.google.com/webstore/detail/' + ExtId
          else if Pos('edge.microsoft.com/extensionwebstorebase/v1/crx',
            UpdateURL) > 0 then
            URL := 'https://microsoftedge.microsoft.com/addons/detail/' + ExtId
          else
            URL := '';

          Enabled := Enabled;

          var
          Value := Manifest.GetValue('name');
          if Assigned(Value) then
            Name := Value.Value;

          Value := Manifest.GetValue('description');
          if Assigned(Value) then
            Description := Value.Value;

          Value := Manifest.GetValue('version');
          if Assigned(Value) then
            Version := Value.Value;

          Value := Manifest.GetValue('homepage_url');
          if Assigned(Value) then
            HomepageURL := Value.Value;
        end;
      end;

      if Length(Result) > 0 then
        OutputExtensions(Result);

    finally
      JSONContent.Free;
    end;
  except
    on E: Exception do
      WriteLn('Error reading extensions: ', E.Message);
  end;
end;

procedure TChromiumExtensionHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumExtensionHelper.OutputHuman(const Extensions: TExtensionItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_extensions.txt',
    [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in Extensions do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'ID: ', Item.ID);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Enabled: ', Item.Enabled);
      WriteLn(OutputFile, 'Name: ', Item.Name);
      WriteLn(OutputFile, 'Description: ', Item.Description);
      WriteLn(OutputFile, 'Version: ', Item.Version);
      WriteLn(OutputFile, 'Homepage: ', Item.HomepageURL);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn(Format('[%s] Extensions saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumExtensionHelper.OutputJSON(const Extensions: TExtensionItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JsonString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in Extensions do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('id', TJSONString.Create(Item.ID));
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('enabled', TJSONBool.Create(Item.Enabled));
      JSONObject.AddPair('name', TJSONString.Create(Item.Name));
      JSONObject.AddPair('description', TJSONString.Create(Item.Description));
      JSONObject.AddPair('version', TJSONString.Create(Item.Version));
      JSONObject.AddPair('homepage', TJSONString.Create(Item.HomepageURL));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_extensions.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    // Convert JSON to string
    JsonString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JsonString := StringReplace(JsonString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JsonString);

    WriteLn(Format('[%s] Extensions saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumExtensionHelper.OutputCSV(const Extensions: TExtensionItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_extensions.csv',
    [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'ID,URL,Enabled,Name,Description,Version,HomepageURL');

    for var Item in Extensions do
    begin
      WriteLn(OutputFile, Format('%s,%s,%s,%s,%s,%s,%s', [Item.ID, Item.URL,
        LowerCase(BoolToStr(Item.Enabled, True)), Item.Name, Item.Description,
        Item.Version, Item.HomepageURL]));
    end;

    WriteLn(Format('[%s] Extensions saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumExtensionHelper.OutputExtensions(const Extensions
  : TExtensionItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(Extensions);
    ofJSON:
      OutputJSON(Extensions);
    ofCSV:
      OutputCSV(Extensions);
  end;
end;

function TChromiumExtensionHelper.GetExtensionCount: Integer;
begin
  Result := Length(GetExtensions);
end;

constructor TChromiumExtensionHelper.Create(const AProfilePath: string;
  ABrowserKind: TBrowserKind = bkChrome);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FBrowserKind := ABrowserKind;
  FOutputFormat := ofCSV;
end;

destructor TChromiumExtensionHelper.Destroy;
begin
  inherited;
end;

end.
