// T017 entry file storage; extracted CEnRealStore, unchanged file protocol. No trading transport.
#ifndef VELO_ENTRY_STATE_FILE_MQH
#define VELO_ENTRY_STATE_FILE_MQH
#include "EntryTransport.mqh"
#include "ExitStateFile.mqh"
#include "ExitInstanceLock.mqh"

class CEnRealStore : public CEnStore
  {
   bool              m_held;
public:
   CEnRealStore(void) {m_held=false;}
   virtual bool Lock(const string key)
     {
      string why;
      return(EL_Acquire(key,m_held,why));
     }
   virtual void Unlock(const string key) {EL_Release(key,m_held);}
   virtual bool Exists(const string name) {return(ESF_Exists(name));}
   virtual bool Read(const string name,string &text) {return(ESF_ReadAll(name,text));}
   virtual bool Write(const string name,const string text)
     {
      string tmp=name+ESF_TMP_SUFFIX;
      if(ESF_Exists(tmp)) return(false);                 // a leftover temporary file: recover by hand first
      if(!ESF_WriteAll(tmp,text)) {FileDelete(tmp); return(false);}
      string back;
      if(!ESF_ReadAll(tmp,back) || back!=text) {FileDelete(tmp); return(false);}
      ResetLastError();
      if(!FileMove(tmp,0,name,FILE_REWRITE)) {FileDelete(tmp); return(false);}
      return(ESF_ReadAll(name,back) && back==text);
     }
  };

// Only executor-produced logical names; never paths. Invalid names fail closed.
string EFS_Name(const string logical,const bool lock=false,const bool selftest=false)
  {
   string prefix=(lock ? "VELO_T013_LOCK_" : "VELO_T013_ENTRY_");
   if(StringFind(logical,prefix)!=0) return("");
   int n=StringLen(logical);
   string stem=logical;
   if(!lock)
     {
      if(n<6 || StringSubstr(logical,n-6)!=".state") return("");
      stem=StringSubstr(logical,0,n-6);
     }
   if(StringLen(stem)<=StringLen(prefix)) return("");
   for(int i=0;i<StringLen(stem);i++)
     {
      ushort ch=StringGetCharacter(stem,i);
      if(!((ch>=65 && ch<=90) || (ch>=97 && ch<=122) || (ch>=48 && ch<=57) || ch==95)) return("");
     }
   string name=(selftest ? "VELO_T017_SELFTEST_" : "VELO_T016_FAKE_")+logical;
   if(StringLen(name)>(lock ? 63 : 240)) return("");
   return(name);
  }

class CEnFakeFileStore : public CEnStore
  {
private:
   CEnRealStore m_disk;
   bool m_selftest;
   string m_key;
public:
   CEnFakeFileStore(const bool selftest=false) {m_selftest=selftest; m_key="";}
   virtual bool Lock(const string key)
     {
      string name=EFS_Name(key,true,m_selftest);
      if(name=="" || m_key!="") return(false);
      if(!m_disk.Lock(name)) return(false);
      m_key=key;
      return(true);
     }
   virtual void Unlock(const string key)
     {
      if(m_key=="" || m_key!=key) return;
      m_disk.Unlock(EFS_Name(key,true,m_selftest));
      m_key="";
     }
   virtual bool Exists(const string name)
     {
      string mapped=EFS_Name(name,false,m_selftest);
      return(mapped=="" ? true : m_disk.Exists(mapped));
     }
   virtual bool Read(const string name,string &text)
     {
      text="";
      string mapped=EFS_Name(name,false,m_selftest);
      if(mapped=="") return(false);
      return(m_disk.Read(mapped,text));
     }
   virtual bool Write(const string name,const string text)
     {
      string mapped=EFS_Name(name,false,m_selftest);
      if(mapped=="") return(false);
      return(m_disk.Write(mapped,text));
     }
  };
#endif
