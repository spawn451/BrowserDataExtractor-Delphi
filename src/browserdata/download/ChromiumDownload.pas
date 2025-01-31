unit ChromiumDownload;

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

  TDownloadItem = record
    TargetPath: string;
    URL: string;
    TotalBytes: Int64;
    StartTime: TDateTime;
    EndTime: TDateTime;
    MimeType: string;
  end;

  TDownloadItems = TArray<TDownloadItem>;

  TChromiumDownloadHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_Chromium_DOWNLOAD = 'SELECT target_path, tab_url, total_bytes, ' +
      'strftime(''%Y-%m-%d %H:%M:%S'', start_time/1000000 - 11644473600, ''unixepoch'', ''localtime'') as formatted_start_time, '
      + 'strftime(''%Y-%m-%d %H:%M:%S'', end_time/1000000 - 11644473600, ''unixepoch'', ''localtime'') as formatted_end_time, '
      + 'mime_type FROM downloads';

    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Downloads: TDownloadItems);
    procedure OutputJSON(const Downloads: TDownloadItems);
    procedure OutputCSV(const Downloads: TDownloadItems);
    procedure OutputDownloads(const Downloads: TDownloadItems);
    function ChromiumTimeToDateTime(TimeStamp: Int64): TDateTime;

  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetDownloads: TDownloadItems;
    procedure SortDownloadsBySize(var Downloads: TDownloadItems);
    function GetDownloadCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TChromiumDownloadHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, ' ', '_', [rfReplaceAll]);
end;

function TChromiumDownloadHelper.GetBrowserPrefix: string;
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

function TChromiumDownloadHelper.ChromiumTimeToDateTime(TimeStamp: Int64)
  : TDateTime;
const
  ChromiumTimeStart = 11644473600; // Seconds between 1601-01-01 and 1970-01-01
begin
  Result := UnixToDateTime((TimeStamp div 1000000) - ChromiumTimeStart);
end;

procedure TChromiumDownloadHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumDownloadHelper.OutputHuman(const Downloads: TDownloadItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_downloads.txt', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in Downloads do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'Target Path: ', Item.TargetPath);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Size: ', Item.TotalBytes);
      WriteLn(OutputFile, 'Start Time: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.StartTime));
      WriteLn(OutputFile, 'End Time: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.EndTime));
      WriteLn(OutputFile, 'MIME Type: ', Item.MimeType);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn(Format('[%s] Downloads saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumDownloadHelper.OutputJSON(const Downloads: TDownloadItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in Downloads do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('targetPath', TJSONString.Create(Item.TargetPath));
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('totalBytes', TJSONNumber.Create(Item.TotalBytes));
      JSONObject.AddPair('startTime', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.StartTime));
      JSONObject.AddPair('endTime', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.EndTime));
      if Item.MimeType <> '' then
        JSONObject.AddPair('mimeType', TJSONString.Create(Item.MimeType));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_downloads.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn(Format('[%s] Downloads saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumDownloadHelper.OutputCSV(const Downloads: TDownloadItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_downloads.csv', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'TargetPath,URL,TotalBytes,StartTime,EndTime,MimeType');

    for var Item in Downloads do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%d","%s","%s","%s"',
        [StringReplace(Item.TargetPath, '"', '""', [rfReplaceAll]),
        StringReplace(Item.URL, '"', '""', [rfReplaceAll]), Item.TotalBytes,
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.StartTime),
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.EndTime),
        StringReplace(Item.MimeType, '"', '""', [rfReplaceAll])]));
    end;

    WriteLn(Format('[%s] Downloads saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumDownloadHelper.OutputDownloads(const Downloads
  : TDownloadItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(Downloads);
    ofJSON:
      OutputJSON(Downloads);
    ofCSV:
      OutputCSV(Downloads);
  end;
end;

constructor TChromiumDownloadHelper.Create(const AProfilePath: string;
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

destructor TChromiumDownloadHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TChromiumDownloadHelper.GetDownloads: TDownloadItems;
var
  Query: TUniQuery;
  DownloadDb, TempDb: string;
begin
  SetLength(Result, 0);
  DownloadDb := TPath.Combine(FProfilePath, 'History');
  // Downloads are in History DB

  if not FileExists(DownloadDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('downloads_%s.sqlite',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(DownloadDb, TempDb);
    FSQLiteConnection.Database := TempDb;
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_Chromium_DOWNLOAD;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          TargetPath := Query.FieldByName('target_path').AsString;
          URL := Query.FieldByName('tab_url').AsString;
          TotalBytes := Query.FieldByName('total_bytes').AsLargeInt;

          var
          FS := TFormatSettings.Create;
          FS.DateSeparator := '-';
          FS.TimeSeparator := ':';
          FS.ShortDateFormat := 'yyyy-mm-dd';
          FS.LongTimeFormat := 'hh:nn:ss';

          var
          StartTimeStr := Query.FieldByName('formatted_start_time').AsString;
          try
            StartTime := StrToDateTime(StartTimeStr, FS);
          except
            on E: Exception do
            begin
              WriteLn('Error parsing start time: ' + StartTimeStr + ' - ' +
                E.Message);
              StartTime := 0;
            end;
          end;

          var
          EndTimeStr := Query.FieldByName('formatted_end_time').AsString;
          try
            EndTime := StrToDateTime(EndTimeStr, FS);
          except
            on E: Exception do
            begin
              WriteLn('Error parsing end time: ' + EndTimeStr + ' - ' +
                E.Message);
              EndTime := 0;
            end;
          end;

          MimeType := Query.FieldByName('mime_type').AsString;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
      begin
        SortDownloadsBySize(Result);
        OutputDownloads(Result);
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

procedure TChromiumDownloadHelper.SortDownloadsBySize(var Downloads
  : TDownloadItems);
var
  i, j: Integer;
  temp: TDownloadItem;
begin
  for i := Low(Downloads) to High(Downloads) - 1 do
    for j := i + 1 to High(Downloads) do
      if Downloads[i].TotalBytes < Downloads[j].TotalBytes then
      begin
        temp := Downloads[i];
        Downloads[i] := Downloads[j];
        Downloads[j] := temp;
      end;
end;

function TChromiumDownloadHelper.GetDownloadCount: Integer;
var
  Query: TUniQuery;
  DownloadDb, TempDb: string;
begin
  Result := 0;
  DownloadDb := TPath.Combine(FProfilePath, 'History');
  // Downloads are in History DB

  if not FileExists(DownloadDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('downloads_%s.sqlite',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(DownloadDb, TempDb);
    FSQLiteConnection.Database := TempDb;
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := 'SELECT COUNT(*) as count FROM downloads';
      Query.Open;
      Result := Query.FieldByName('count').AsInteger;
    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

end.
