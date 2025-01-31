unit FirefoxHistory;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.DateUtils,
  System.JSON,
  Uni,
  SQLiteUniProvider;

type
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  THistoryItem = record
    ID: Int64;
    Title: string;
    URL: string;
    VisitCount: Integer;
    LastVisitTime: TDateTime;
  end;

  THistoryItems = TArray<THistoryItem>;

  TFirefoxHistoryHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_FIREFOX_HISTORY = 'SELECT id, url, ' +
      'strftime(''%Y-%m-%d %H:%M:%S'', COALESCE(last_visit_date, 0)/1000000, ''unixepoch'', ''localtime'') as formatted_visit_date, '
      + 'COALESCE(title, '''') as title, visit_count FROM moz_places';

    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const History: THistoryItems);
    procedure OutputJSON(const History: THistoryItems);
    procedure OutputCSV(const History: THistoryItems);
    procedure OutputHistory(const History: THistoryItems);
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetHistory: THistoryItems;
    procedure SortHistoryByVisitCount(var History: THistoryItems);
    function GetHistoryCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxHistoryHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

procedure TFirefoxHistoryHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxHistoryHelper.OutputHuman(const History: THistoryItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_history.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in History do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Title: ', Item.Title);
      WriteLn(OutputFile, 'Visit Count: ', Item.VisitCount);
      if Item.LastVisitTime > 0 then
        WriteLn(OutputFile, 'Last Visit: ',
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.LastVisitTime));
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] History saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxHistoryHelper.OutputJSON(const History: THistoryItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in History do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('title', TJSONString.Create(Item.Title));
      JSONObject.AddPair('visitCount', TJSONNumber.Create(Item.VisitCount));

      if Item.LastVisitTime > 0 then
        JSONObject.AddPair('lastVisit', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.LastVisitTime))
      else
        JSONObject.AddPair('lastVisit', TJSONString.Create(''));

      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_history.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] History saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxHistoryHelper.OutputCSV(const History: THistoryItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_history.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'URL,Title,VisitCount,LastVisitTime');

    for var Item in History do
    begin
      WriteLn(OutputFile, Format('"%s","%s",%d,"%s"',
        [StringReplace(Item.URL, '"', '""', [rfReplaceAll]),
        StringReplace(Item.Title, '"', '""', [rfReplaceAll]), Item.VisitCount,
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.LastVisitTime)]));
    end;

    WriteLn('[FIREFOX] History saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxHistoryHelper.OutputHistory(const History: THistoryItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(History);
    ofJSON:
      OutputJSON(History);
    ofCSV:
      OutputCSV(History);
  end;
end;

constructor TFirefoxHistoryHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV;
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TFirefoxHistoryHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TFirefoxHistoryHelper.GetHistory: THistoryItems;
var
  Query: TUniQuery;
  HistoryDb, TempDb: string;
  FS: TFormatSettings;
begin
  SetLength(Result, 0);
  HistoryDb := TPath.Combine(FProfilePath, 'places.sqlite');

  if not FileExists(HistoryDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('places_%s.sqlite', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(HistoryDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_FIREFOX_HISTORY;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          ID := Query.FieldByName('id').AsLargeInt;
          URL := Query.FieldByName('url').AsString;
          Title := Query.FieldByName('title').AsString;
          VisitCount := Query.FieldByName('visit_count').AsInteger;

          var VisitDateStr := Query.FieldByName('formatted_visit_date').AsString;

          try
            FS := TFormatSettings.Create;
            FS.DateSeparator := '-';
            FS.TimeSeparator := ':';
            FS.ShortDateFormat := 'yyyy-mm-dd';
            FS.LongTimeFormat := 'hh:nn:ss';
            LastVisitTime := StrToDateTime(VisitDateStr, FS);
          except
            on E: Exception do
            begin
              WriteLn('Error parsing visit date: ' + VisitDateStr + ' - ' + E.Message);
              LastVisitTime := 0;
            end;
          end;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
        OutputHistory(Result);

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    // Delete temporary database copy
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

procedure TFirefoxHistoryHelper.SortHistoryByVisitCount
  (var History: THistoryItems);
var
  i, j: Integer;
  temp: THistoryItem;
begin
  for i := Low(History) to High(History) - 1 do
    for j := i + 1 to High(History) do
      if History[i].VisitCount > History[j].VisitCount then
      begin
        temp := History[i];
        History[i] := History[j];
        History[j] := temp;
      end;
end;

function TFirefoxHistoryHelper.GetHistoryCount: Integer;
var
  Query: TUniQuery;
  HistoryDb: string;
begin
  Result := 0;
  HistoryDb := TPath.Combine(FProfilePath, 'places.sqlite');

  if not FileExists(HistoryDb) then
    Exit;

  FSQLiteConnection.Database := HistoryDb;

  try
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := 'SELECT COUNT(*) as count FROM moz_places';
      Query.Open;
      Result := Query.FieldByName('count').AsInteger;
    finally
      Query.Free;
    end;
  except
    on E: Exception do
      WriteLn('Error getting history count: ', E.Message);
  end;
end;

end.
