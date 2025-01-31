unit FirefoxSessionStorage;

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

  TSessionStorageItem = record
    URL: string;
    Key: string;
    Value: string;
  end;

  TSessionStorageItems = TArray<TSessionStorageItem>;

  TFirefoxSessionStorageHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_FIREFOX_SESSIONSTORAGE = 'SELECT originKey, key, value FROM webappsstore2';
    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const SessionStorage: TSessionStorageItems);
    procedure OutputJSON(const SessionStorage: TSessionStorageItems);
    procedure OutputCSV(const SessionStorage: TSessionStorageItems);
    procedure OutputSessionStorage(const SessionStorage: TSessionStorageItems);
    function ParseOriginKey(const OriginKey: string): string;
    function ReverseString(const Str: string): string;

  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetSessionStorage: TSessionStorageItems;
    function GetSessionStorageCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxSessionStorageHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

function TFirefoxSessionStorageHelper.ReverseString(const Str: string): string;
var
  i: Integer;
begin
  SetLength(Result, Length(Str));
  for i := 1 to Length(Str) do
    Result[i] := Str[Length(Str) - i + 1];
end;

function TFirefoxSessionStorageHelper.ParseOriginKey(const OriginKey: string): string;
var
  Parts: TArray<string>;
  Host: string;
begin
  // Split originKey (e.g., "moc.buhtig.:https:443")
  Parts := OriginKey.Split([':']);
  if Length(Parts) = 3 then
  begin
    // Reverse the host part and remove leading dot if present
    Host := ReverseString(Parts[0]);
    if Host.StartsWith('.') then
      Host := Host.Substring(1);

    // Format: scheme://host:port
    Result := Format('%s://%s:%s', [Parts[1], Host, Parts[2]]);
  end
  else
    Result := OriginKey;
end;

procedure TFirefoxSessionStorageHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxSessionStorageHelper.OutputHuman(const SessionStorage: TSessionStorageItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_sessionstorage.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in SessionStorage do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Key: ', Item.Key);
      WriteLn(OutputFile, 'Value: ', Item.Value);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] SessionStorage saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxSessionStorageHelper.OutputJSON(const SessionStorage: TSessionStorageItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in SessionStorage do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('key', TJSONString.Create(Item.Key));
      JSONObject.AddPair('value', TJSONString.Create(Item.Value));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_sessionstorage.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] SessionStorage saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxSessionStorageHelper.OutputCSV(const SessionStorage: TSessionStorageItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_sessionstorage.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'URL,Key,Value');

    for var Item in SessionStorage do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s"',
        [StringReplace(Item.URL, '"', '""', [rfReplaceAll]),
         StringReplace(Item.Key, '"', '""', [rfReplaceAll]),
         StringReplace(Item.Value, '"', '""', [rfReplaceAll])]));
    end;

    WriteLn('[FIREFOX] SessionStorage saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxSessionStorageHelper.OutputSessionStorage(const SessionStorage: TSessionStorageItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(SessionStorage);
    ofJSON:
      OutputJSON(SessionStorage);
    ofCSV:
      OutputCSV(SessionStorage);
  end;
end;

constructor TFirefoxSessionStorageHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV; // Default to CSV
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TFirefoxSessionStorageHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TFirefoxSessionStorageHelper.GetSessionStorage: TSessionStorageItems;
var
  Query: TUniQuery;
  SessionStorageDb, TempDb: string;
begin
  SetLength(Result, 0);
  SessionStorageDb := TPath.Combine(FProfilePath, 'webappsstore.sqlite');

  if not FileExists(SessionStorageDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('webappsstore_%s.sqlite', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(SessionStorageDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_FIREFOX_SESSIONSTORAGE;
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
        OutputSessionStorage(Result);

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

function TFirefoxSessionStorageHelper.GetSessionStorageCount: Integer;
var
  Query: TUniQuery;
  SessionStorageDb: string;
begin
  Result := 0;
  SessionStorageDb := TPath.Combine(FProfilePath, 'webappsstore.sqlite');

  if not FileExists(SessionStorageDb) then
    Exit;

  FSQLiteConnection.Database := SessionStorageDb;

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
      WriteLn('Error getting sessionStorage count: ', E.Message);
  end;
end;

end.
