/// Web: there is no dart:io; network failures arrive as http.ClientException.
bool isNetworkError(Object e) => false;
