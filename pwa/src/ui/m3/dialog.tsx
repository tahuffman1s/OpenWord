import type { ComponentChildren } from 'preact';
import { Icon, type IconName } from './icon';
import { showDialog, useOverlay } from './overlay';
import { TextButton } from './buttons';

export interface AlertDialogProps {
  icon?: IconName | string;
  title?: ComponentChildren;
  children?: ComponentChildren;
  actions?: ComponentChildren;
}

/** The body of a dialog: optional icon, a title, content, actions. */
export function AlertDialog({ icon, title, children, actions }: AlertDialogProps) {
  return (
    <div class={icon ? 'm3-dialog--icon' : undefined} style="display:contents">
      {icon && (
        <div class="m3-dialog__icon">
          <Icon name={icon} />
        </div>
      )}
      {title && <h2 class="m3-dialog__title" style={icon ? 'text-align:center' : undefined}>{title}</h2>}
      {children && <div class="m3-dialog__body">{children}</div>}
      {actions && <div class="m3-dialog__actions">{actions}</div>}
    </div>
  );
}

/** A dialog button that closes the dialog with a result. */
export function DialogAction({ children, result, destructive, onClick }: { children: ComponentChildren; result?: unknown; destructive?: boolean; onClick?: () => void }) {
  const overlay = useOverlay();
  return (
    <TextButton
      destructive={destructive}
      onClick={() => {
        onClick?.();
        overlay.close(result);
      }}
    >
      {children}
    </TextButton>
  );
}

/** Asks a yes/no question; answers true for the confirming button. */
export function confirm(options: { title: ComponentChildren; body?: ComponentChildren; confirmLabel?: string; cancelLabel?: string; destructive?: boolean; icon?: IconName | string }): Promise<boolean> {
  return showDialog<boolean>(
    <AlertDialog
      icon={options.icon}
      title={options.title}
      actions={
        <>
          <DialogAction result={false}>{options.cancelLabel ?? 'Cancel'}</DialogAction>
          <DialogAction result={true} destructive={options.destructive}>
            {options.confirmLabel ?? 'OK'}
          </DialogAction>
        </>
      }
    >
      {options.body}
    </AlertDialog>,
  ).then((r) => r === true);
}

/** Tells the reader something, with one button. */
export function alert(title: ComponentChildren, body?: ComponentChildren, label = 'OK'): Promise<void> {
  return showDialog<void>(
    <AlertDialog title={title} actions={<DialogAction>{label}</DialogAction>}>
      {body}
    </AlertDialog>,
  ).then(() => undefined);
}
