// Throwaway shim: just enough MQL5 for H4Structure.mqh / H4Bias.mqh (evidence tool, not MetaEditor)
#pragma once
#include <string>
#include <vector>
#include <deque>
#include <cstdio>
#include <cstdarg>
#include <cstdint>
#include <cassert>
#include <cmath>
#include <cstring>
#include <ctime>
#include <initializer_list>
typedef long long datetime;
typedef unsigned short ushort;
typedef long long llong;
struct string {
  std::string v;
  string() {}
  string(const char* s) : v(s) {}
  string(const std::string& s) : v(s) {}
  string operator+(const string& o) const { return string(v + o.v); }
  string& operator+=(const string& o) { v += o.v; return *this; }
  bool operator==(const string& o) const { return v == o.v; }
  bool operator!=(const string& o) const { return v != o.v; }
  bool operator<(const string& o) const { return v < o.v; }
};
#define S(x) string(x)
template <class T> struct MArr {
  std::deque<T> a;
  MArr() {}
  MArr(int n) : a(n) {}
  MArr(std::initializer_list<T> l) : a(l) {}
  T& operator[](int i) { if (i < 0 || i >= (int)a.size()) { fprintf(stderr, "ARRAY OUT OF RANGE %d of %d\n", i, (int)a.size()); abort(); } return a[i]; }
  const T& operator[](int i) const { if (i < 0 || i >= (int)a.size()) { fprintf(stderr, "ARRAY OUT OF RANGE %d of %d\n", i, (int)a.size()); abort(); } return a[i]; }
};
template <class T> int ArrayResize(MArr<T>& m, int n, int reserve = 0) { m.a.resize(n); return n; }
template <class T> int ArraySize(const MArr<T>& m) { return (int)m.a.size(); }
template <class T> int ArrayCopy(MArr<T>& dst, const MArr<T>& src, int ds = 0, int ss = 0, int cnt = -1) {
  if (cnt < 0) cnt = (int)src.a.size() - ss;
  if ((int)dst.a.size() < ds + cnt) dst.a.resize(ds + cnt);
  for (int i = 0; i < cnt; i++) dst.a[ds + i] = src.a[ss + i];
  return cnt;
}
struct MqlRates { datetime time; double open, high, low, close; long tick_volume; int spread; long real_volume; };
struct MqlDateTime { int year, mon, day, hour, min, sec, day_of_week, day_of_year; };
inline void TimeToStruct(datetime t, MqlDateTime& d) { time_t tt = (time_t)t; struct tm g; gmtime_r(&tt, &g); d.year = g.tm_year + 1900; d.mon = g.tm_mon + 1; d.day = g.tm_mday; d.hour = g.tm_hour; d.min = g.tm_min; d.sec = g.tm_sec; d.day_of_week = g.tm_wday; d.day_of_year = g.tm_yday; }
inline string TimeToString(datetime t, int flags = 0) { MqlDateTime d; TimeToStruct(t, d); char b[64]; snprintf(b, sizeof b, "%04d.%02d.%02d %02d:%02d", d.year, d.mon, d.day, d.hour, d.min); return string(b); }
#define TIME_DATE 1
#define TIME_MINUTES 2
inline string ShortToString(ushort c) { return string(std::string(1, (char)c)); }
inline string IntegerToString(long long x) { return string(std::to_string(x)); }
inline string DoubleToString(double x, int digits) { char b[64]; snprintf(b, sizeof b, "%.*f", digits, x); return string(b); }
inline double NormalizeDouble(double x, int d) { char b[64]; snprintf(b, sizeof b, "%.*f", d, x); return atof(b); }
inline int StringLen(const string& s) { return (int)s.v.size(); }
inline string StringSubstr(const string& s, int pos, int len = -1) { if (pos >= (int)s.v.size()) return string(""); return string(len < 0 ? s.v.substr(pos) : s.v.substr(pos, len)); }
inline int StringFind(const string& s, const string& sub, int start = 0) { size_t p = s.v.find(sub.v, start); return p == std::string::npos ? -1 : (int)p; }
inline ushort StringGetCharacter(const string& s, int i) { return (ushort)(unsigned char)s.v[i]; }
inline int StringCompare(const string& a, const string& b) { return a.v < b.v ? -1 : (a.v > b.v ? 1 : 0); }
inline int StringSplit(const string& s, ushort sep, MArr<string>& out) { out.a.clear(); std::string cur; for (char c : s.v) { if ((unsigned char)c == sep) { out.a.push_back(string(cur)); cur.clear(); } else cur += c; } out.a.push_back(string(cur)); return (int)out.a.size(); }
inline void fmt_arg(std::string& fmt_acc) {}
template <class T> auto fa(const T& x) { return x; }
inline const char* fa(const string& x) { return x.v.c_str(); }
template <class... A> string StringFormat(const string& f, A... a) { char b[2048]; snprintf(b, sizeof b, f.v.c_str(), fa(a)...); return string(b); }
template <class... A> void PrintFormat(const string& f, A... a) { printf(f.v.c_str(), fa(a)...); printf("\n"); }
inline void Print_one(const string& s) { printf("%s", s.v.c_str()); }
template <class... A> void Print(A... a) { (Print_one(a), ...); printf("\n"); }
inline double StringToDouble(const string& s) { return atof(s.v.c_str()); }
template <class T> void ZeroMemory(T& x) { x = T(); }
