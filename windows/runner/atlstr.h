#ifndef ATLSTR_H_COMPAT
#define ATLSTR_H_COMPAT

#include <windows.h>
#include <tchar.h>
#include <ole2.h>
#include <strsafe.h>
#include <string>
#include <vector>

class CW2A {
public:
  CW2A(LPCWSTR lpsz) {
    if (!lpsz) {
      m_psz = nullptr;
      return;
    }
    int len = WideCharToMultiByte(CP_ACP, 0, lpsz, -1, NULL, 0, NULL, NULL);
    if (len > 0) {
      str_.resize(len);
      WideCharToMultiByte(CP_ACP, 0, lpsz, -1, &str_[0], len, NULL, NULL);
      m_psz = &str_[0];
    } else {
      m_psz = nullptr;
    }
  }
  operator LPSTR() const { return const_cast<LPSTR>(m_psz); }
  operator LPCSTR() const { return m_psz; }
  LPSTR m_psz = nullptr;
private:
  std::string str_;
};

class CA2W {
public:
  CA2W(LPCSTR lpsz) {
    if (!lpsz) {
      m_psz = nullptr;
      return;
    }
    int len = MultiByteToWideChar(CP_ACP, 0, lpsz, -1, NULL, 0);
    if (len > 0) {
      wstr_.resize(len);
      MultiByteToWideChar(CP_ACP, 0, lpsz, -1, &wstr_[0], len);
      m_psz = &wstr_[0];
    } else {
      m_psz = nullptr;
    }
  }
  operator LPWSTR() const { return const_cast<LPWSTR>(m_psz); }
  operator LPCWSTR() const { return m_psz; }
  LPWSTR m_psz = nullptr;
private:
  std::wstring wstr_;
};

typedef std::string CStringA;
typedef std::wstring CStringW;
#ifdef UNICODE
typedef std::wstring CString;
#else
typedef std::string CString;
#endif

#endif // ATLSTR_H_COMPAT
