unit UEscapeDialog;

interface

uses
  System.Classes,
  Winapi.Windows,
  Vcl.Controls, Vcl.Forms;

type
  TEscapeDialogForm = class(TForm)
  protected
    procedure CMDialogKey(var aMessage: TCMDialogKey); message CM_DIALOGKEY;
    procedure KeyDown(var aKey: Word; aShift: TShiftState); override;
  end;

implementation

procedure TEscapeDialogForm.CMDialogKey(var aMessage: TCMDialogKey);
begin
  if aMessage.CharCode = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    aMessage.Result := 1;
  end else begin
    inherited;
  end;
end;

procedure TEscapeDialogForm.KeyDown(var aKey: Word; aShift: TShiftState);
begin
  if aKey = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    aKey := 0;
  end else begin
    inherited;
  end;
end;

end.
