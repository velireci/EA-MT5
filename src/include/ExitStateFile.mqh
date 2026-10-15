// T011 persistence of the 2R partial-close state: the THIN FILE LAYER over ExitStateCodec.mqh (all serialisation / validation lives there). Mirrors the
// FileStore model of tests/t011_persist_reference.py. The ONLY place that touches files. NOT a trading module: no order, no broker read, no clock, no retry.
// Save protocol: validate+encode -> refuse unless the existing target is a valid record of the SAME identity with generation-1 (or none, and generation 1)
// and no temporary file is left -> write "<name>.tmp" -> flush -> close -> read it back and compare -> FileMove over the target (FILE_REWRITE) -> read the
// target back and compare. Any failure returns false: the caller MUST NOT send the request when the save of its PENDING + INTENT record did not return true.
// GUARANTEE LIMITS: the sequence is NOT atomic (neither on the file system nor with the broker); a crash between the steps leaves a temporary file, which
// the load treats as RECOVERY_REQUIRED (never silently promoted); a file restored from a backup cannot be detected as older; the terminal file API
// (FileMove semantics, flush) is UNVERIFIED until the owner runs T011_PersistFileTest. Files live in the terminal's MQL5/Files sandbox (no FILE_COMMON).
#ifndef VELO_EXIT_STATE_FILE_MQH
#define VELO_EXIT_STATE_FILE_MQH

#include "ExitStateCodec.mqh"

#define ESF_TMP_SUFFIX ".tmp"

string ESF_FileName(const long login,const ulong position_id)
  {
   return("VELO_T011_EXIT_"+IntegerToString(login)+"_"+IntegerToString((long)position_id)+".state");
  }

// false = the file exists but could not be read completely
bool ESF_ReadAll(const string name,string &text)
  {
   text="";
   ResetLastError();
   int h=FileOpen(name,FILE_READ|FILE_BIN);
   if(h==INVALID_HANDLE) return(false);
   ulong size=FileSize(h);
   if(size>(ulong)(ESC_MAX_TEXT+16))                 // checked BEFORE the conversion to int
     {
      FileClose(h);
      return(false);
     }
   int isize=(int)size;
   uchar a[];
   int n=0;
   if(isize>0)
      n=(int)FileReadArray(h,a,0,isize);
   FileClose(h);
   if(n!=isize) return(false);
   text=(isize>0 ? CharArrayToString(a,0,n) : "");
   return(true);
  }

// writes the exact bytes of an ASCII text; true only if every byte was written
bool ESF_WriteAll(const string name,const string text)
  {
   ResetLastError();
   int h=FileOpen(name,FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) return(false);
   uchar a[];
   int len=StringLen(text);
   int n=StringToCharArray(text,a,0,len);
   bool ok=(n==len);
   if(ok && len>0)
      ok=((int)FileWriteArray(h,a,0,len)==len);
   if(ok) FileFlush(h);
   FileClose(h);
   return(ok);
  }

bool ESF_Exists(const string name) {return(FileIsExist(name));}

// Returns true when the record was written, verified and moved into place.
bool ESF_Save(const string name,const SEsRecord &rec,string &reason)
  {
   reason="";
   string text;
   if(!ESC_Encode(rec,text,reason))
     {
      reason="ENCODE_REFUSED: "+reason;
      return(false);
     }
   string tmp=name+ESF_TMP_SUFFIX;
   if(ESF_Exists(tmp))
     {
      reason="LEFTOVER_TMP: recover first";
      return(false);
     }
   if(ESF_Exists(name))
     {
      string old;
      SEsRecord cur;
      string why;
      if(!ESF_ReadAll(name,old) || !ESC_Decode(old,cur,why))
        {
         reason="EXISTING_FILE_UNUSABLE: recover first";
         return(false);
        }
      if(!ESC_IdentityEqual(cur.id,rec.id))
        {
         reason="EXISTING_FILE_OTHER_IDENTITY";
         return(false);
        }
      if(cur.generation>=ESC_MAX_GEN || rec.generation!=cur.generation+1)
        {
         reason=StringFormat("GENERATION_NOT_NEXT: %d after %d",rec.generation,cur.generation);
         return(false);
        }
     }
   else
      if(rec.generation!=1)
        {
         reason="FIRST_GENERATION_MUST_BE_1";
         return(false);
        }
   if(!ESF_WriteAll(tmp,text))
     {
      reason="TMP_WRITE_FAILED";
      FileDelete(tmp);
      return(false);
     }
   string back;
   if(!ESF_ReadAll(tmp,back) || back!=text)
     {
      reason="TMP_READBACK_DIFFERS";
      FileDelete(tmp);
      return(false);
     }
   ResetLastError();
   if(!FileMove(tmp,0,name,FILE_REWRITE))
     {
      reason=StringFormat("MOVE_FAILED: error %d",GetLastError());
      FileDelete(tmp);
      return(false);
     }
   if(!ESF_ReadAll(name,back) || back!=text)
     {
      reason="TARGET_READBACK_DIFFERS";
      return(false);
     }
   return(true);
  }

// Restores the state of `expected` (never the broker). `st` is always safe to use afterwards: restored, or BLOCKED / NEEDS_RECONCILIATION.
void ESF_Load(const string name,const SEsIdentity &expected,SEaState &st,SEsRestore &o)
  {
   bool tmp=ESF_Exists(name+ESF_TMP_SUFFIX);
   string text="";
   bool have=false;
   if(ESF_Exists(name))
     {
      if(!ESF_ReadAll(name,text))
        {
         ESC_RestoreInit(o);
         EA_StateInit(st);
         st.status=EA_ST_BLOCKED;
         st.reason="RECOVERY_REQUIRED: UNREADABLE: the state file exists but could not be read completely";
         o.reason="UNREADABLE: the state file exists but could not be read completely";
         return;
        }
      have=true;
     }
   ESC_Restore(have,text,expected,tmp,st,o);
  }

// Creates the first (IDLE, generation 1) record for a position. Never overwrites: an existing file or temporary file is refused.
bool ESF_InitFresh(const string name,const SEsIdentity &identity,string &reason)
  {
   if(ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX))
     {
      reason="ALREADY_EXISTS: never overwrite";
      return(false);
     }
   SEsRecord r;
   ESC_RecordInit(r);
   r.generation=1;
   r.id=identity;
   return(ESF_Save(name,r,reason));
  }
#endif
