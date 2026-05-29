import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

String createObjectUrlFromBytes(Uint8List bytes) {
  final fn = globalContext.callMethod(
    'eval'.toJS,
    '(function(a){return URL.createObjectURL(new Blob([a],{type:"application/pdf"}));})'.toJS,
  ) as JSFunction;
  return (fn.callAsFunction(null, bytes.toJS) as JSString).toDart;
}

void triggerWebDownload(String objectUrl, String filename) {
  final fn = globalContext.callMethod(
    'eval'.toJS,
    '''(function(url, name) {
      var a = document.createElement('a');
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    })'''.toJS,
  ) as JSFunction;
  fn.callAsFunction(null, objectUrl.toJS, filename.toJS);
}
