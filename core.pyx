import os
import time
import datetime
import sys
import Queue as Queue2
import gc
import shutil
import argparse

import pysam

from itertools import izip
from multiprocessing import Process,Queue
from abc import ABCMeta, abstractmethod

#Tasks are started by parabam.FileReader. Once started 
#they will carryout a predefined task on the provided
#subset of reads (task_set).
class TTask(Process):

    __metaclass__ = ABCMeta

    def __init__(self,object parent_bam,object task_set,
                     object outqu,int curproc,
                     object const,str parent_class):
        
        Process.__init__(self)
        self._task_set = task_set
        self._outqu = outqu
        self._curproc = curproc
        self._temp_dir = const.temp_dir
        self._parent_class = parent_class
        self._parent_bam = parent_bam
        self.const = const

    def run(self):
        #print "Task Started %d" % (self.pid,)
        results = self.__generate_results__()
        #print "Task Finished %d" % (self.pid,)
        results["total"] = len(self._task_set)

        self._outqu.put(CorePackage(results=results,
                                curproc=self._curproc,
                                parent_class=self._parent_class))
        #Trying to control mem useage
        del self._task_set
        gc.collect()

    #Generate a dictionary of results using self._task_set
    @abstractmethod
    def __generate_results__(self):
        #Should always return a dictionary
        pass

cdef class Handler:

    def __init__(self,object parent_bam, object output_paths,object inqu,
                object const,object pause_qu,dict out_qu_dict,object report=True):

        self._parent_bam = parent_bam
        self._inqu = inqu
        self._pause_qu = pause_qu
        self._out_qu_dict = out_qu_dict

        self._report = report
        self._stats = {}

        self.const = const
        self._verbose = const.verbose
        self._output_paths = output_paths

        self._periodic_interval = 10

        self._destroy = False
        self._finished = False

        if const.verbose == 1:
            self._verbose = True
            self._update_output = self.__level_1_output__
        elif const.verbose == 2 or const.verbose == True:
            #In the case verbose is simply "True" or "level 2"
            self._verbose = True
            self._update_output = self.__level_2_output__
        else:#catching False and -v0
            self._verbose = False
            self._update_output = self.__level_2_output__

    def __standard_output__(self,out_str):
        sys.stdout.write(out_str + "\n")
        sys.stdout.flush()

    def __level_1_output__(self,out_str):
        #BUG! the fact this makes a call to __total_reads__ is ridiculous
        #this is making calls to a sub class method and just expecting it to be there.

        total_procd = self.__total_reads__()
        time = out_str.partition("Time: ")[2]
        sys.stdout.write("[Update] Processed: %d Time: %s\n" % (total_procd,time))
        sys.stdout.flush()

    def __level_2_output__(self,outstr):
        sys.stdout.write("\r" + outstr)
        sys.stdout.flush()

    #Must be overwritten if stats architecture is modififed
    def __total_reads__(self):
        if self._stats == {}:
            return 0
        return self._stats["total"]

    def listen(self,update_interval):
        destroy = self._destroy

        cdef int iterations = 0
        cdef int start_time = time.time()
        cdef int dealt  = 0
        cdef int curproc = 0

        update_output = self._update_output #speedup alias
        periodic_interval = self._periodic_interval #speedup alias
        finished = self.__is_finished__

        while not finished():
            iterations += 1
            #Listen for a process coming in...
            try:
                new_package = self._inqu.get(False)
                if type(new_package) == DestroyPackage:
                    self._destroy = True

                if not new_package.results == {}:#If results are present...
                    self.__new_package_action__(new_package) #Handle the results
                    dealt += 1
                    if type(new_package) == CorePackage:
                        curproc = new_package.curproc

            except Queue2.Empty:
                #Queue empty. Continue with loop
                time.sleep(.5)

            if iterations % periodic_interval == 0: 
                self.__periodic_action__(iterations)

            if self._verbose and self._report and iterations % update_interval == 0:
                outstr = self.__format_update__(curproc,start_time)
                update_output(outstr)

        self._inqu.close()
        self.__handler_exit__()

    def __is_finished__(self):
        if not self._destroy or not self._finished:
            return False
        return True

    def __format_update__(self,curproc,start_time):
        stats = []

        for stat_name in self._stats:
            if type(self._stats[stat_name]) is dict: #Account for divided stats.
                stat_update_str = "[%s] " % (stat_name,)
                for data in self._stats[stat_name]:
                    stat_update_str += "%s:%d " % (data,self._stats[stat_name][data])
                stat_update_str = stat_update_str[:-1] + " "

                stats.append(stat_update_str)
            else:
                stats.append("%s: %d" % (stat_name,self._stats[stat_name]))

        statstr = " ".join(stats)
        return "\r%s | Tasks: %d Time: %d " %\
                (statstr,curproc,self.__secs_since__(start_time),)

    #This code is a little ugly. Essentially, given a results
    #dictionary, it will go through and create a sensible output
    #string.
    def __auto_handle__(self,results,stats):
        for key_one in results:
            if type(results[key_one]) is int:
                if key_one in stats:
                    stats[key_one] += results[key_one]
                else:
                    stats[key_one] = results[key_one]
            elif type(results[key_one]) is dict:
                for key_two in results[key_one]:
                    if type(results[key_one][key_two]) is int:
                        if key_two in stats:
                            stats[key_two] += results[key_one][key_two]
                        else:
                            stats[key_two] = results[key_one][key_two]

    def __secs_since__(self,since):
        return int(time.time() - since)

    def __periodic_action__(self,iterations):
        #Overwrite with something that needs
        #to be done occasionally.       
        pass

    def __new_package_action__(self,new_package,**kwargs):
        #Handle the output of a task. Input will always be of type
        #parabam.Package. New results action should always call
        #self.__auto_handle__(new_package.results)
        pass

    def __handler_exit__(self,**kwargs):
        #When the handler finishes, do this
        pass

class Task(Process):

    def __init__(self,parent_path,inqu,outqu,size,header,temp_dir,engine):
        super(Task,self).__init__()
        self._parent_path = parent_path
        self._outqu = outqu
        self._inqu = inqu
        self._size = size
        self._header = header
        self._temp_dir = temp_dir
        self._engine = engine

    def run(self):
        bamfile = pysam.AlignmentFile(self._parent_path,"rb")
        bamiter = bamfile.fetch(until_eof=True)
        next_read = bamiter.next
        engine = self._engine

        cdef int size = self._size
        cdef int sub_count = 0
        cdef int dealt = 0

        while True:
            try:
                package = self._inqu.get(False)
                
                if type(package) == DestroyPackage:
                    bamfile.close()
                    del bamiter
                    del bamfile
                    break

                seek = package
                temp = pysam.AlignmentFile("%s/%d_%d_%d_subset.bam" %\
                    (self._temp_dir,dealt,self.pid,time.time()),"wb",header = self._header)
                
                bamfile.seek(seek)
                time.sleep(.01)
                
                for i in xrange(size):
                    read = next_read()
                    if engine(read,{},bamfile):
                       temp.write(read)
                       sub_count += 1

                results = {"temp_paths":{"subset":temp.filename},
                           "counts": {"subset":sub_count},
                           "total" : size}
                
                sub_count = 0
                dealt += 1
                temp.close()
                time.sleep(0.005)
                #print self.pid,"send"
                self._outqu.put(CorePackage(results=results,
                                curproc=6,
                                parent_class=self.__class__.__name__))

            except Queue2.Empty:
                time.sleep(5)
            except StopIteration:
                pass

        return
        
#The FileReader iterates over a BAM, subsets reads and
#then starts a parbam.Task process on the subsetted reads
class FileReader(Process):
    def __init__(self,str input_path,int proc_id,object outqu,int task_n,object const):
        super(FileReader,self).__init__()

        self._input_path = input_path
        self._proc_id = proc_id
        
        self._outqu = outqu

        self._task_n = task_n
        self._task_size = const.task_size
        self._reader_n = const.reader_n

        self._temp_dir = const.temp_dir

        self._debug = const.debug
        self._engine = const.user_engine

    #Find data pertaining to assocd and all reads 
    #and divide pertaining to the chromosome that it is aligned to
    def run(self):
        parent_bam = pysam.AlignmentFile(self._input_path,"rb")
        parent_iter = parent_bam.fetch(until_eof=True)
        parent_generator = self.__bam_generator__(parent_iter)
        if self._debug:
            parent_generator = self.__debug_generator__(parent_iter)

        task_qu = Queue()

        tasks = [Task(parent_path=self._input_path,
                      inqu=task_qu,
                      outqu=self._outqu,
                      size=self._task_size,
                      header=parent_bam.header,
                      temp_dir=self._temp_dir,
                      engine=self._engine) for i in xrange(self._task_n)]

        for task in tasks:
            task.start()

        for i,command in enumerate(parent_generator):
            time.sleep(.005)
            task_qu.put(parent_bam.tell())

        for n in xrange(self._task_n+1):
            task_qu.put(DestroyPackage())
        time.sleep(3)
        parent_bam.close()
        task_qu.close()
        return

    def __debug_generator__(self,parent_iter):
        cdef int proc_id = self._proc_id
        cdef int reader_n = self._reader_n
        cdef int iterations = 0
        cdef int task_size = self._task_size

        while True:            
            try:
                if iterations % reader_n == proc_id:
                    yield True
                for x in xrange(task_size):
                    parent_iter.next()
                iterations += 1

                if iterations == 50:
                    break

            except StopIteration:
                break
        return

    def __bam_generator__(self,parent_iter):
        cdef int proc_id = self._proc_id
        cdef int reader_n = self._reader_n
        cdef int iterations = 0
        cdef int task_size = self._task_size

        while True:            
            try:
                if iterations % reader_n == proc_id:
                    yield True
                for x in xrange(task_size):
                    parent_iter.next()
                iterations += 1
            except StopIteration:
                break
        return
        
class Leviathon(object):
    #Leviathon takes objects of file_readers and handlers and
    #chains them together.
    def __init__(self,object const,dict handler_bundle,
                 list handler_order,list queue_names,int update):

        self.const = const
        self._handler_bundle  = handler_bundle
        self._handler_order = handler_order
        self._update = update
        self._queue_names = queue_names
    
    def run(self,input_path,output_paths):
        parent = ParentAlignmentFile(input_path)

        default_qus = self.__create_queues__(self._queue_names) 

        handlers_objects,handler_inqus = self.__create_handlers__(self._handler_order,
                                                          self._handler_bundle,
                                                          default_qus,parent,output_paths)
        handlers = self.__get_handlers__(handlers_objects)

        task_n = self.__get_task_n__(self.const,handlers)
        file_reader_bundles = self.__get_file_reader_bundles__(default_qus,parent,
                                                               task_n,self.const)
        file_readers,pause_qus = self.__get_file_readers__(file_reader_bundles)

        #Start file_readers
        for file_reader in file_readers:
            file_reader.start()
            time.sleep(2)

        #Start handlers:
        for handler in handlers:
            handler.start()

        #Wait for file_readers to finish
        for file_reader in file_readers:
            file_reader.join()

        #Destory handlers
        for handler,queue in izip(handlers,handler_inqus):
            queue.put(DestroyPackage())
            handler.join()

        del default_qus
        del file_reader_bundles
        del file_readers
        del pause_qus
        del handler_inqus
        del handlers_objects
        del handlers

        gc.collect()

    def __get_task_n__(self,object const,handlers):
        task_n = (const.total_procs - len(handlers) - const.reader_n) / const.reader_n
        if task_n > 0:
            return task_n
        else:
            return 1

    def __get_file_readers__(self,file_reader_bundles):
        file_readers = []
        for bundle in file_reader_bundles: 
            file_reader = FileReader(**bundle)
            file_readers.append(file_reader)
        return file_readers,[]

    def __proc_id_generator__(self,reader_n):
        for i in reversed(xrange(reader_n)):
            yield i

    def __get_file_reader_bundles__(self,default_qus,parent,task_n,object const):
        bundles = []

        for proc_id in self.__proc_id_generator__(const.reader_n):
            current_bundle = {}
            current_bundle["input_path"] = parent.filename
            current_bundle["proc_id"] = proc_id
            current_bundle["task_n"] = task_n
            current_bundle["outqu"] = default_qus["main"]
            current_bundle["const"] = const 

            bundles.append(current_bundle)

        return bundles
 
    def __create_queues__(self,queue_names):
        queues = {}
        for name in queue_names:
            queues[name] = Queue()
        queues["pause"] = Queue()
        return queues

    def __create_handlers__(self,handler_order,handler_bundle,
                            queues,parent_bam,output_paths):
        handlers = []
        handler_inqus = []

        for handler_class in handler_order:
            handler_args = dict(handler_bundle[handler_class])

            handler_args["parent_bam"] = parent_bam
            handler_args["output_paths"] = output_paths

            #replace placeholder with queues
            handler_args["pause_qu"] = queues["pause"]
            handler_args["inqu"] = queues[handler_args["inqu"]]
            handler_args["out_qu_dict"] = dict(\
                    [(name,queues[name]) for name in handler_args["out_qu_dict"] ])

            handler_inqus.append(handler_args["inqu"])
            handlers.append(handler_class(**handler_args))

        return handlers,handler_inqus

    def __get_handlers__(self,handlers):
        handler_processes = []
        for handler in handlers:
            hpr = Process(target=handler.listen,args=(self._update,))
            handler_processes.append(hpr)
        return handler_processes

#Provides a conveinant way for providing an Interface to parabam
#programs. Includes default command_args and framework for 
#command-line and programatic invocation. 
class Interface(object):

    __metaclass__ = ABCMeta

    def __init__(self,temp_dir):
        self._temp_dir = temp_dir

    def __introduce__(self,name):
        intro =  "%s has started. Start Time: " % (name,)\
            + datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d %H:%M:%S')
        underline = "-" * len(intro)
        print intro
        print underline

    def __goodbye__(self,name):
        print "%s has finished. End Time: " % (name,)\
            + datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d %H:%M:%S')

    def __sort_and_index__(self,fnm,verbose=False,tempDir=".",name=False):
        if not os.path.exists(fnm+".bai"):
            if verbose: print "%s is not indexed. Sorting and creating index file." % (fnm,)
            tempsort_path = self.__get_unique_temp_path__("SORT",temp_dir=self._temp_dir)
            optStr = "-nf" if name else "-f"
            pysam.sort(optStr,fnm,tempsort_path)
            os.remove(fnm)
            os.rename(tempsort_path,fnm)
            if not name: pysam.index(fnm)

    def __get_unique_temp_path__(self,temp_type,temp_dir="."):
        #TODO: Duplicated from parabam.interface.merger. Find a way to reformat code
        #to remove this duplication
        return "%s/%sTEMP%d.bam" % (temp_dir,temp_type,int(time.time()),)

    def __get_group__(self,bams,names=[],multi=1):
        if multi == 0:
            multi = 1
        if names == []:
            names = [self.__get_basename__(path) for path in bams]
        for i in xrange(0,len(bams),multi):
            yield (bams[i:i+multi],names[i:i+multi])

    def __get_basename__(self,path):
        base,ext = os.path.splitext(os.path.basename(path))
        return base

    def default_parser(self):

        parser = ParabamParser(conflict_handler='resolve',
                    formatter_class=argparse.RawTextHelpFormatter)

        parser.add_argument('-p',type=int,nargs='?',default=4
            ,help="The maximum amount of processes you wish parabam to use. This should"\
                  "be less than or equal to the amount of processor cores in your machine.")
        parser.add_argument('-s',type=int,nargs='?',default=250000
            ,help="The amount of reads considered by each distributed task.")
        return parser

    @abstractmethod
    def run_cmd(self,parser):
        #This is usualy just a function that
        #takes an argparse parser and turns 
        #passes the functions to the run function
        pass

    @abstractmethod
    def run(self):
        pass

    @abstractmethod
    def get_parser(self):
        pass

class ParabamParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_help()
        sys.stderr.write('\nerror: %s\n' % message)
        sys.exit(2)

class Const(object):
    
    def __init__(self,temp_dir,verbose,task_size,total_procs,**kwargs):
        #TODO: Update with real required const values
        self.temp_dir = temp_dir
        self.verbose = verbose
        self.task_size = task_size
        self.total_procs = total_procs

        for key, val in kwargs.items():
            setattr(self,key,val)

    def add(self,key,val):
        setattr(self,key,val)

class Package(object):
    def __init__(self,results):
        self.results = results

class CorePackage(Package):
    def __init__(self,results,curproc,parent_class):
        super(CorePackage,self).__init__(results)
        self.curproc = curproc
        self.parent_class = parent_class

class DestroyPackage(Package):
    def __init__(self):
        super(DestroyPackage,self).__init__(results={})
        self.destroy = True

class ParentAlignmentFile(object):
    
    def __init__(self,path,input_is_sam=False):
        has_index = os.path.exists(os.path.join("%s%s" % (path,".bai")))

        if input_is_sam:
            mode = "r"
        else:
            mode = "rb"
        parent = pysam.AlignmentFile(path,mode)
        self.filename = parent.filename
        self.references = parent.references
        self.header = parent.header
        self.lengths = parent.lengths

        if has_index:
            self.nocoordinate = parent.nocoordinate
            self.nreferences = parent.nreferences
            self.unmapped = parent.unmapped
        else:
            self.mapped = 0
            self.nocoordinate = 0
            self.nreferences = 0
            self.unmapped = 0

        parent.close()

    def getrname(self,tid):
        return self.references[tid]

    def gettid(self,reference):
        for i,ref in enumerate(self.references):
            if reference == ref:
                return i
        return -1


#And they all lived happily ever after...
