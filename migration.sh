#!/bin/bash

usage_() {
	echo "usage:"
	echo "migration.sh 配置文件 命令"
	echo "命令:"
	echo -e "\tnew 文件名"
	echo -e "\tmigrate"
	echo -e "\trevert"
}

new() {
	file_name=${migration_file_path}/`date +%Y-%m-%d-%H-%M-%S`_${1}.mig

	echo -e "MIGRATION\n" > ${file_name}
	echo -e "MIGRATION_END\n\n" >> ${file_name}
	echo -e "REVERT\n" >> ${file_name}
	echo -e "REVERT_END" >> ${file_name}
}

get_new_files_() {
	last_file=$*
	ret=
	for file in `ls ${migration_file_path} | grep \.mig$ | sort`; do
		if [[ $last_file == "" ]]; then
			ret=$ret:$file
		elif [[ $last_file == *"$file"* ]]; then
			ret=$ret
		else
			ret=$ret:$file
		fi
	done
	echo $ret
	return 0
}

get_migrated_files_() {
	echo `mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "select files from db_migration order by id desc" 2>> migration_error.log`
	return 0
}

get_section_from_file_() {
	file_name=$1
	sep=$2
	st=`grep -n ^${sep}$ $file_name`
	if [[ $? == 0 ]]; then
		ed=`grep -n ^${sep}_END$ $file_name`
		if [[ $? == 0 ]]; then
			st=`echo $st | cut -d: -f 1`
			st=`expr $st + 1`
			ed=`echo $ed | cut -d: -f 1`
			ed=`expr $ed - 1`
			sql=`sed -n "$st,${ed}p" $file_name`
			echo `echo $sql | sed 's/\n//g'`
		fi
	fi
}

migrate() {
	last_file=`get_migrated_files_`
	matched_files=`get_new_files_ $last_file`
	
	`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "create table if not exists db_migration (id int primary key auto_increment, inserted_time datetime, files varchar(512))" 2> migration_error.log`

	if [[ $? == 1 ]]; then
		echo "创建元信息数据库失败"
		return 0
	fi

	idx=0
	matched_files=`echo $matched_files | sed "s/:/ /g"`
	for file in $matched_files; do
		sql=`get_section_from_file_ $migration_file_path/$file MIGRATION`
		`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "$sql" 2>> migration_error.log`
		if [[ $? == 1 ]]; then
			break
		fi
		idx=`expr $idx + 1`
	done

	matched_files=( $matched_files )
	if [[ 0 == ${#matched_files[@]} ]]; then
		echo "没有新文件"
	fi

	fail_files=${matched_files[@]:$idx}
	success_files=${matched_files[@]:0:$idx}
	success_files2=($success_files)

	for (( i = 0; i < $idx; i+=4 )); do
		files=${success_files2[@]:$i:4}
		now_time=`date +%Y-%m-%d\ %H:%M:%S`
		`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "insert into db_migration(inserted_time, files) values(\"$now_time\", \"$files\")" 2>> migration_error.log`
		if [[ $? == 1 ]]; then
			echo "FATAL: 元信息修改错误"
		fi
	done

	if [[ $idx != 0 ]]; then
		echo "执行成功: ${success_files}"
	fi

	if [[ $idx != ${#matched_files[@]} ]]; then
		echo "执行失败: $fail_files"
	fi
}

revert(){
	ret=(`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "select files from db_migration order by id desc limit 1" 2> migration_error.log`)

	if [[ "${ret[@]}" == "" ]]; then
		echo "所有文件都已经回滚"
		return 0
	fi

	ret=(${ret[@]:1})
	nret=${#ret[@]}
	for (( i = $nret; i > 0; i-- )); do
		files[$nret - i]=${ret[$i - 1]}
	done

	idx=0
	for file in `echo ${files[@]}`; do
		sql=`get_section_from_file_ $migration_file_path/$file REVERT`
		`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "$sql" 2>> migration_error.log`
		if [[ $? == 1 ]]; then
			break
		fi
		idx=`expr $idx + 1`
	done

	fail_files=${files[@]:$idx}
	success_files=${files[@]:0:$idx}
	if [[ $idx != 0 ]]; then
		`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "delete from db_migration order by id desc limit 1" 2>> migration_error.log`
		if [[ $? == 1 ]]; then
			echo "FATAL: 元信息修改错误"
			echo "回滚成功: ${success_files}"
		else
			echo "回滚成功: ${success_files}"
		fi
	fi
	
	if [[ $idx != ${#files[@]} ]]; then
		fail_index=`expr $nret - $idx`
		need_rewrite=${ret[@]:0:$fail_index}
		now_time=`date +%Y-%m-%d\ %H:%M:%S`
		if [[ $idx != 0 ]]; then
			`mysql -u$migration_user -h$migration_host -p $migration_db -p$migration_pwd -e "insert into db_migration(inserted_time, files) values(\"$now_time\", \"$need_rewrite\")" 2>> migration_error.log`
			if [[ $? == 1 ]]; then
				echo "FATAL: 元信息修改错误"
			fi
		fi
		echo "回滚失败: $fail_files"
	fi
}

if [[ $# < 2 ]]; then
	usage_
else
	source $1
	case $2 in
		new )
			new $3;;
		migrate )
			migrate;;
		revert )
			revert;;
		debug )
			$3 $4 $5 $6 $7 $8 $9 $10 $11 $12 $13 $14 $15 $16 $17;;
		* )
			usage_;;
	esac
fi
