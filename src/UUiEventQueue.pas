unit UUiEventQueue;

interface

uses
  System.Generics.Collections, System.SyncObjs,
  UModels;

{$SCOPEDENUMS ON}

type
  TUiEventKind = (uekLog, uekProgressStart, uekProgressUpdate, uekProgressEnd,
    uekRepoResult, uekScanFinished, uekActionResult, uekClearResults);

  TUiEvent = record
    Kind: TUiEventKind;
    Text: string;
    ProgressMode: TProgressMode;
    ProgressMax: Integer;
    ProgressValue: Integer;
    RepoStatus: TRepoStatus;
    ActionTag: Integer;
    ActionSucceeded: Boolean;
    ActionError: string;
    AlertText: string;
  end;

  TUiEventQueue = class
  private
    fQueue: TQueue<TUiEvent>;
    fLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const aEvent: TUiEvent);
    function TryDequeue(out aEvent: TUiEvent): Boolean;
    procedure Clear;
  end;

implementation

constructor TUiEventQueue.Create;
begin
  inherited Create;
  fQueue := TQueue<TUiEvent>.Create;
  fLock := TCriticalSection.Create;
end;

procedure TUiEventQueue.Clear;
begin
  fLock.Enter;
  try
    fQueue.Clear;
  finally
    fLock.Leave;
  end;
end;

destructor TUiEventQueue.Destroy;
begin
  fLock.Free;
  fQueue.Free;
  inherited;
end;

procedure TUiEventQueue.Enqueue(const aEvent: TUiEvent);
begin
  fLock.Enter;
  try
    fQueue.Enqueue(aEvent);
  finally
    fLock.Leave;
  end;
end;

function TUiEventQueue.TryDequeue(out aEvent: TUiEvent): Boolean;
begin
  Result := False;
  fLock.Enter;
  try
    if fQueue.Count > 0 then
    begin
      aEvent := fQueue.Dequeue;
      Result := True;
    end;
  finally
    fLock.Leave;
  end;
end;

end.
