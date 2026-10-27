import { Copy, ShieldCheck, Trash2, Users } from 'lucide-react'

type Member = { user_id: string; display_name: string; role: string; joined_at?: string }

type Props = {
  name: string
  email: string
  role: string
  teamName: string
  inviteCode: string
  members: Member[]
  isAdmin: boolean
  currentUserId: string
  onCopyInvite: () => void
  onRemoveMember: (member: Member) => void
}

export default function ProfilePage({ name, email, role, teamName, inviteCode, members, isAdmin, currentUserId, onCopyInvite, onRemoveMember }: Props) {
  return <div className="content profile-content">
    <div className="page-heading">
      <div><div className="eyebrow">MY ACCOUNT</div><h1>{isAdmin ? '관리자 페이지' : '마이페이지'}</h1><p>내 계정 정보와 팀 공간 정보를 확인할 수 있어요.</p></div>
    </div>

    <section className="panel profile-summary">
      <div className="profile-summary-heading"><div className="avatar self profile-avatar">{name.slice(0, 1)}</div><div><h2>{name}</h2><span>{role === 'admin' ? '관리자' : '팀원'}</span></div></div>
      <div className="profile-fields">
        <div><small>이메일</small><b>{email || '이메일 정보 없음'}</b></div>
        <div><small>소속 팀</small><b>{teamName}</b></div>
        <div><small>권한</small><b>{role === 'admin' ? '관리자' : '팀원'}</b></div>
      </div>
    </section>

    {isAdmin && <>
      <section className="panel invite-admin-card">
        <div><span className="profile-section-icon"><Users size={17}/></span><div><h2>팀원 초대</h2><p>초대 코드를 새 팀원에게 전달해 주세요. 가입 후 코드로 팀에 합류할 수 있어요.</p></div></div>
        <code>{inviteCode || '초대 코드 없음'}</code>
        <button className="button primary" onClick={onCopyInvite} disabled={!inviteCode}><Copy size={15}/> 초대 코드 복사</button>
      </section>

      <section className="panel team-admin-panel">
        <div className="panel-heading"><div><h3>현재 팀원</h3><p>{members.length}명이 팀 공간을 함께 사용하고 있어요.</p></div><ShieldCheck size={18}/></div>
        <div className="managed-member-list">{members.map(member => <article className="managed-member" key={member.user_id}>
          <div className="avatar">{member.display_name.slice(0, 1)}</div>
          <div className="managed-member-info"><b>{member.display_name}{member.user_id === currentUserId && <em>나</em>}</b><small>{member.role === 'admin' ? '관리자' : '팀원'}</small></div>
          {member.role === 'admin' ? <span className="managed-role">관리자</span> : <button className="button outline small remove-member" onClick={() => onRemoveMember(member)}><Trash2 size={14}/> 팀원 내보내기</button>}
        </article>)}</div>
        <p className="profile-note">팀원을 내보내면 해당 계정은 이 팀 공간에 다시 초대받기 전까지 접근할 수 없습니다. 업무 기록은 유지됩니다.</p>
      </section>
    </>}
  </div>
}
