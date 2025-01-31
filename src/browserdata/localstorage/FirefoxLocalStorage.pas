unit FirefoxLocalStorage;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.JSON,
  Uni,
  SQLiteUniProvider;

type
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TLocalStorageItem = record
    URL: string;
    Key: string;
    Value: string;
  end;

  TLocalStorageItems = TArray<TLocalStorageItem>;

  TFirefoxLocalStorageHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_FIREFOX_LOCALSTORAGE = 'SELECT originKey, key, value FROM webappsstore2';
    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const LocalStorage: TLocalStorageItems);
    procedure OutputJSON(const LocalStorage: TLocalStorageItems);
    procedure OutputCSV(const LocalStorage: TLocalStorageItems);
    procedure OutputLocalStorage(const LocalStorage: TLocalStorageItems);
    function ParseOriginKey(const OriginKey: string): string;

  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetLocalStorage: TLocalStorageItems;
    function GetLocalStorageCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxLocalStorageHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

function TFirefoxLocalStorageHelper.ParseOriginKey(const OriginKey: string): string;
var
  Parts: TArray<string>;
  Host: string;
  i: Integer;
begin
  // Split originKey (e.g., "moc.buhtig.:https:443")
  Parts := OriginKey.Split([':']);
  if Length(Parts) >= 3 then
  begin
    // Reverse the host part
    Host := '';
    for i := Length(Parts[0]) downto 1 do
      Host := Host + Parts[0][i];

    // Remove leading dot if present
    if Host.StartsWith('.') then
      Host := Host.Substring(1);

    // Reconstruct URL
    Result := Format('%s://%s:%s', [Parts[1], Host, Parts[2]]);
  end
  else
    Result := OriginKey;
end;

procedure TFirefoxLocalStorageHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxLocalStorageHelper.OutputHuman(const LocalStorage: TLocalStorageItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_localstorage.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in LocalStorage do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Key: ', Item.Key);
      WriteLn(OutputFile, 'Value: ', Item.Value);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] LocalStorage saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxLocalStorageHelper.OutputJSON(const LocalStorage: TLocalStorageItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in LocalStorage do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('key', TJSONString.Create(Item.Key));
      JSONObject.AddPair('value', TJSONString.Create(Item.Value));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_localstorage.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] LocalStorage saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxLocalStorageHelper.OutputCSV(const LocalStorage: TLocalStorageItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_localstorage.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'URL,Key,Value');

    for var Item in LocalStorage do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s"',
        [StringReplace(Item.URL, '"', '""', [rfReplaceAll]),
         StringReplace(Item.Key, '"', '""', [rfReplaceAll]),
         StringReplace(Item.Value, '"', '""', [rfReplaceAll])]));
    end;

    WriteLn('[FIREFOX] LocalStorage saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxLocalStorageHelper.OutputLocalStorage(const LocalStorage: TLocalStorageItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(LocalStorage);
    ofJSON:
      OutputJSON(LocalStorage);
    ofCSV:
      OutputCSV(LocalStorage);
  end;
end;

constructor TFirefoxLocalStorageHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV; // Default to CSV
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TFirefoxLocalStorageHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TFirefoxLocalStorageHelper.GetLocalStorage: TLocalStorageItems;
var
  Query: TUniQuery;
  LocalStorageDb, TempDb: string;
begin
  SetLength(Result, 0);
  LocalStorageDb := TPath.Combine(FProfilePath, 'webappsstore.sqlite');

  if not FileExists(LocalStorageDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('webappsstore_%s.sqlite', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(LocalStorageDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_FIREFOX_LOCALSTORAGE;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          URL := ParseOriginKey(Query.FieldByName('originKey').AsString);
          Key := Query.FieldByName('key').AsString;
          Value := Query.FieldByName('value').AsString;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
        OutputLocalStorage(Result);

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

function TFirefoxLocalStorageHelper.GetLocalStorageCount: Integer;
var
  Query: TUniQuery;
  LocalStorageDb: string;
begin
  Result := 0;
  LocalStorageDb := TPath.Combine(FProfilePath, 'webappsstore.sqlite');

  if not FileExists(LocalStorageDb) then
    Exit;

  FSQLiteConnection.Database := LocalStorageDb;

  try
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := 'SELECT COUNT(*) as count FROM webappsstore2';
      Query.Open;
      Result := Query.FieldByName('count').AsInteger;
    finally
      Query.Free;
    end;
  except
    on E: Exception do
      WriteLn('Error getting localStorage count: ', E.Message);
  end;
end;

end.
