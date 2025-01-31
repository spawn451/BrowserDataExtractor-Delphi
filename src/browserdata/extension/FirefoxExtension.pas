unit FirefoxExtension;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.DateUtils,
  System.JSON;

type
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TExtensionItem = record
    ID: string;
    Name: string;
    Description: string;
    Version: string;
    HomepageURL: string;
    Enabled: Boolean;
  end;

  TExtensionItems = TArray<TExtensionItem>;

  TFirefoxExtensionHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;

    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Extensions: TExtensionItems);
    procedure OutputJSON(const Extensions: TExtensionItems);
    procedure OutputCSV(const Extensions: TExtensionItems);
    procedure OutputExtensions(const Extensions: TExtensionItems);
    function ParseExtensionsJSON(const JSONContent: string): TExtensionItems;
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetExtensions: TExtensionItems;
    function GetExtensionCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxExtensionHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

procedure TFirefoxExtensionHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxExtensionHelper.OutputHuman(const Extensions
  : TExtensionItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_extensions.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in Extensions do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'ID: ', Item.ID);
      WriteLn(OutputFile, 'Name: ', Item.Name);
      WriteLn(OutputFile, 'Description: ', Item.Description);
      WriteLn(OutputFile, 'Version: ', Item.Version);
      WriteLn(OutputFile, 'HomepageURL: ', Item.HomepageURL);
      WriteLn(OutputFile, 'Enabled: ', Item.Enabled.ToString(True));
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] Extensions saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxExtensionHelper.OutputJSON(const Extensions: TExtensionItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in Extensions do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('id', TJSONString.Create(Item.ID));
      JSONObject.AddPair('name', TJSONString.Create(Item.Name));
      JSONObject.AddPair('description', TJSONString.Create(Item.Description));
      JSONObject.AddPair('version', TJSONString.Create(Item.Version));
      JSONObject.AddPair('homepageURL', TJSONString.Create(Item.HomepageURL));
      JSONObject.AddPair('enabled', TJSONBool.Create(Item.Enabled));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_extensions.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] Extensions saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxExtensionHelper.OutputCSV(const Extensions: TExtensionItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_extensions.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'ID,Name,Description,Version,HomepageURL,Enabled');

    for var Item in Extensions do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s","%s","%s","%s"',
        [StringReplace(Item.ID, '"', '""', [rfReplaceAll]),
        StringReplace(Item.Name, '"', '""', [rfReplaceAll]),
        StringReplace(Item.Description, '"', '""', [rfReplaceAll]),
        StringReplace(Item.Version, '"', '""', [rfReplaceAll]),
        StringReplace(Item.HomepageURL, '"', '""', [rfReplaceAll]),
        BoolToStr(Item.Enabled, True)]));
    end;

    WriteLn('[FIREFOX] Extensions saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxExtensionHelper.OutputExtensions(const Extensions
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

function TFirefoxExtensionHelper.ParseExtensionsJSON(const JSONContent: string)
  : TExtensionItems;
var
  JSONObject: TJSONObject;
  AddonsArray: TJSONArray;
  Addon, DefaultLocale: TJSONObject;
  JSONValue: TJSONValue;
  Location: string;
begin
  SetLength(Result, 0);
  try
    JSONObject := TJSONObject.ParseJSONValue(JSONContent) as TJSONObject;
    if not Assigned(JSONObject) then
      Exit;

    try
      // Check if 'addons' array exists and get it
      if not JSONObject.TryGetValue<TJSONArray>('addons', AddonsArray) then
      begin
        WriteLn('Warning: No addons array found in JSON');
        Exit;
      end;

      for var i := 0 to AddonsArray.Count - 1 do
      begin
        try
          if not(AddonsArray.Items[i] is TJSONObject) then
            Continue;

          Addon := AddonsArray.Items[i] as TJSONObject;

          // Get location first
          if not Addon.TryGetValue<string>('location', Location) then
            Continue;

          // Skip system add-ons
          if Location <> 'app-profile' then
            Continue;

          // Get defaultLocale object
          if not Addon.TryGetValue<TJSONObject>('defaultLocale', DefaultLocale)
          then
          begin
            WriteLn('Warning: No defaultLocale found for addon');
            Continue;
          end;

          SetLength(Result, Length(Result) + 1);
          with Result[High(Result)] do
          begin
            // Get ID
            if Addon.TryGetValue<string>('id', ID) = False then
              ID := '';

            // Get Name
            if DefaultLocale.TryGetValue<string>('name', Name) = False then
              Name := '';

            // Get Description
            if DefaultLocale.TryGetValue<string>('description', Description) = False
            then
              Description := '';

            // Get Version
            if Addon.TryGetValue<string>('version', Version) = False then
              Version := '';

            // Get HomepageURL
            if DefaultLocale.TryGetValue<string>('homepageURL', HomepageURL) = False
            then
              HomepageURL := '';

            // Get Enabled status
            if Addon.TryGetValue('active', JSONValue) then
              Enabled := StrToBoolDef(JSONValue.Value, False)
            else
              Enabled := False;
          end;

        except
          on E: Exception do
          begin
            WriteLn('Warning: Error processing extension: ', E.Message);
            Continue;
          end;
        end;
      end;

    finally
      JSONObject.Free;
    end;

  except
    on E: Exception do
    begin
      WriteLn('Error parsing extensions JSON: ', E.Message);
      SetLength(Result, 0);
    end;
  end;
end;

constructor TFirefoxExtensionHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV; // Default to CSV
end;

destructor TFirefoxExtensionHelper.Destroy;
begin
  inherited;
end;

function TFirefoxExtensionHelper.GetExtensions: TExtensionItems;
var
  ExtensionsFile: string;
  JSONContent: string;
begin
  SetLength(Result, 0);
  ExtensionsFile := TPath.Combine(FProfilePath, 'extensions.json');

  if not FileExists(ExtensionsFile) then
    Exit;

  try
    JSONContent := TFile.ReadAllText(ExtensionsFile);
    Result := ParseExtensionsJSON(JSONContent);

    if Length(Result) > 0 then
      OutputExtensions(Result);
  except
    on E: Exception do
      WriteLn('Error reading extensions: ', E.Message);
  end;
end;

function TFirefoxExtensionHelper.GetExtensionCount: Integer;
var
  ExtensionsFile: string;
  JSONContent: string;
  JSONObject: TJSONObject;
  AddonsArray: TJSONArray;
begin
  Result := 0;
  ExtensionsFile := TPath.Combine(FProfilePath, 'extensions.json');

  if not FileExists(ExtensionsFile) then
    Exit;

  try
    JSONContent := TFile.ReadAllText(ExtensionsFile);
    JSONObject := TJSONObject.ParseJSONValue(JSONContent) as TJSONObject;
    if Assigned(JSONObject) then
      try
        AddonsArray := JSONObject.GetValue('addons') as TJSONArray;
        if Assigned(AddonsArray) then
          Result := AddonsArray.Count;
      finally
        JSONObject.Free;
      end;
  except
    on E: Exception do
      WriteLn('Error getting extension count: ', E.Message);
  end;
end;

end.
