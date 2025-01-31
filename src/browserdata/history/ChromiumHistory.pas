unit ChromiumHistory;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.DateUtils,
  System.JSON,
  System.StrUtils,
  Uni,
  SQLiteUniProvider;

type
  TBrowserKind = (bkChrome, bkBrave, bkEdge);

  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  THistoryItem = record
    ID: Int64;
    Title: string;
    URL: string;
    VisitCount: Integer;
    LastVisitTime: TDateTime;
  end;

  THistoryItems = TArray<THistoryItem>;

  TChromiumHistoryHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_Chromium_HISTORY = 'SELECT url, title, visit_count, ' +
      'strftime(''%Y-%m-%d %H:%M:%S'', last_visit_time/1000000-11644473600, ''unixepoch'', ''localtime'') as formatted_visit_date '
      + 'FROM urls';

    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const History: THistoryItems);
    procedure OutputJSON(const History: THistoryItems);
    procedure OutputCSV(const History: THistoryItems);
    procedure OutputHistory(const History: THistoryItems);
    function ChromiumTimeToDateTime(TimeStamp: Int64): TDateTime;

  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetHistory: THistoryItems;
    procedure SortHistoryByVisitCount(var History: THistoryItems);
    function GetHistoryCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TChromiumHistoryHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, ' ', '_', [rfReplaceAll]);
end;

function TChromiumHistoryHelper.GetBrowserPrefix: string;
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

function TChromiumHistoryHelper.ChromiumTimeToDateTime(TimeStamp: Int64)
  : TDateTime;
const
  ChromiumTimeStart = 11644473600; // Seconds between 1601-01-01 and 1970-01-01
begin
  Result := UnixToDateTime((TimeStamp div 1000000) - ChromiumTimeStart);
end;

procedure TChromiumHistoryHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumHistoryHelper.OutputHuman(const History: THistoryItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_history.txt', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in History do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'Title: ', Item.Title);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Visit Count: ', Item.VisitCount);
      WriteLn(OutputFile, 'Last Visit: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.LastVisitTime));
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn(Format('[%s] History saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumHistoryHelper.OutputJSON(const History: THistoryItems);
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
      JSONObject.AddPair('title', TJSONString.Create(Item.Title));
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('visitCount', TJSONNumber.Create(Item.VisitCount));
      JSONObject.AddPair('lastVisit', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.LastVisitTime));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_history.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn(Format('[%s] History saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumHistoryHelper.OutputCSV(const History: THistoryItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_history.csv', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'Title,URL,VisitCount,LastVisit');

    for var Item in History do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%d","%s"',
        [StringReplace(Item.Title, '"', '""', [rfReplaceAll]),
        StringReplace(Item.URL, '"', '""', [rfReplaceAll]), Item.VisitCount,
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.LastVisitTime)]));
    end;

    WriteLn(Format('[%s] History saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumHistoryHelper.OutputHistory(const History: THistoryItems);
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

constructor TChromiumHistoryHelper.Create(const AProfilePath: string;
  ABrowserKind: TBrowserKind = bkChrome);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FBrowserKind := ABrowserKind;
  FOutputFormat := ofCSV;
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TChromiumHistoryHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TChromiumHistoryHelper.GetHistory: THistoryItems;
var
  Query: TUniQuery;
  HistoryDb, TempDb: string;
  FS: TFormatSettings;
begin
  SetLength(Result, 0);
  HistoryDb := TPath.Combine(FProfilePath, 'History');

  if not FileExists(HistoryDb) then
    Exit;

  TempDb := TPath.Combine(TPath.GetTempPath, Format('history_%s.sqlite',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(HistoryDb, TempDb);
    FSQLiteConnection.Database := TempDb;
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_Chromium_HISTORY;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          Title := Query.FieldByName('title').AsString;
          URL := Query.FieldByName('url').AsString;
          VisitCount := Query.FieldByName('visit_count').AsInteger;

          var
          VisitDateStr := Query.FieldByName('formatted_visit_date').AsString;
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
              WriteLn('Error parsing visit date: ' + VisitDateStr + ' - ' +
                E.Message);
              LastVisitTime := 0;
            end;
          end;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
      begin
        SortHistoryByVisitCount(Result);
        OutputHistory(Result);
      end;

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

procedure TChromiumHistoryHelper.SortHistoryByVisitCount
  (var History: THistoryItems);
var
  i, j: Integer;
  temp: THistoryItem;
begin
  for i := Low(History) to High(History) - 1 do
    for j := i + 1 to High(History) do
      if History[i].VisitCount < History[j].VisitCount then
      begin
        temp := History[i];
        History[i] := History[j];
        History[j] := temp;
      end;
end;

function TChromiumHistoryHelper.GetHistoryCount: Integer;
var
  Query: TUniQuery;
  HistoryDb, TempDb: string;
begin
  Result := 0;
  HistoryDb := TPath.Combine(FProfilePath, 'History');

  if not FileExists(HistoryDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('history_%s.sqlite',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(HistoryDb, TempDb);
    FSQLiteConnection.Database := TempDb;
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := 'SELECT COUNT(*) as count FROM urls';
      Query.Open;
      Result := Query.FieldByName('count').AsInteger;
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

end.
