import { Capacitor } from '@capacitor/core';

/** True inside the Android / iPhone app (Capacitor), false in a browser or an installed web app. */
export function isNative(): boolean {
  return Capacitor.isNativePlatform();
}

/** A file name safe for the phone's file system. */
export function safeFileName(name: string): string {
  const s = name.replace(/[\\/:*?"<>|\u0000-\u001f]+/g, '_').trim();
  return s || 'export';
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onerror = () => reject(r.error);
    r.onload = () => resolve(String(r.result).split(',', 2)[1] ?? '');
    r.readAsDataURL(blob);
  });
}

/**
 * Saves a generated file. In a browser it downloads; in the phone app it opens the share sheet
 * (save to Files / Drive, send by e-mail or WhatsApp …), because app web views cannot download.
 */
export async function saveFile(name: string, blob: Blob): Promise<void> {
  if (!isNative()) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    return;
  }
  const [{ Filesystem, Directory }, { Share }] = await Promise.all([import('@capacitor/filesystem'), import('@capacitor/share')]);
  const file = await Filesystem.writeFile({ path: safeFileName(name), data: await blobToBase64(blob), directory: Directory.Cache, recursive: true });
  try {
    await Share.share({ title: name, dialogTitle: name, files: [file.uri] });
  } catch {
    // the person closed the share sheet — nothing to do
  }
}

/** Printing is a browser feature; the phone app shows the page and offers sharing instead. */
export function canPrint(): boolean {
  return !isNative();
}
